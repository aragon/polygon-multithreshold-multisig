// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginUUPSUpgradeable, IDAO} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IMultisig} from "../src/IMultisig.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IPlugin} from "@aragon/osx/core/plugin/IPlugin.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPluginSetup, PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {AragonTest} from "./base/AragonTest.sol";
import {PolygonMultisigSetup} from "../src/PolygonMultisigSetup.sol";
import {PolygonMultisig} from "../src/PolygonMultisig.sol";

import "forge-std/console.sol";

abstract contract PolygonMultisigTest is AragonTest {
    DAO internal dao;
    PolygonMultisig internal plugin;
    PolygonMultisigSetup internal setup;
    address[] members = [address(0xB0b), address(0xdeaf)];
    PolygonMultisig.MultisigSettings multisigSettings =
        PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            minConfirmations: 1,
            emergencyMinApprovals: 1,
            delayDuration: 0.5 days,
            memberOnlyProposalExecution: true,
            minExtraDuration: 0.5 days
        });

    function setUp() public virtual {
        vm.prank(address(0xB0b));
        setup = new PolygonMultisigSetup();
        bytes memory setupData = abi.encode(members, multisigSettings, address(0xB0b));

        (DAO _dao, address _plugin) = createMockDaoWithPlugin(setup, setupData);

        dao = _dao;
        plugin = PolygonMultisig(_plugin);
        vm.roll(block.number + 1);
    }

    function addMemberToPluginWithoutExecution(
        address[] memory _members
    ) internal returns (uint256) {
        vm.stopPrank();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.addAddresses, _members)
        });

        uint256 proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        plugin.multisigSettings();
        vm.warp(block.timestamp + 1 days);
        plugin.confirm(proposalId);

        vm.stopPrank();

        return proposalId;
    }
}

abstract contract PolygonMultisigExtraMembersTest is AragonTest {
    DAO internal dao;
    PolygonMultisig internal plugin;
    PolygonMultisigSetup internal setup;
    address[] members = [address(0xB0b), address(0xDad), address(0xDead), address(0xBeef)];
    PolygonMultisig.MultisigSettings multisigSettings =
        PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            minConfirmations: 1,
            emergencyMinApprovals: 3,
            delayDuration: 0.5 days,
            memberOnlyProposalExecution: false,
            minExtraDuration: 0.5 days
        });

    function setUp() public virtual {
        vm.prank(address(0xB0b));
        setup = new PolygonMultisigSetup();
        bytes memory setupData = abi.encode(members, multisigSettings, address(0xB0b));

        (DAO _dao, address _plugin) = createMockDaoWithPlugin(setup, setupData);

        dao = _dao;
        plugin = PolygonMultisig(_plugin);
        vm.roll(block.number + 1);
    }
}

contract PolygonMultisigInitializeTest is PolygonMultisigTest {
    function test_initialize() public {
        super.setUp();
        assertEq(address(plugin.dao()), address(dao));
        assertEq(plugin.isMember(address(0xB0b)), true);
        (
            bool _onlyListed,
            uint16 _minApprovals,
            uint16 _minConfirmations,
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration,
            bool _memberOnlyProposalExecution,
            uint256 _minExtraDuration
        ) = plugin.multisigSettings();
        assertEq(_onlyListed, multisigSettings.onlyListed);
        assertEq(_minApprovals, multisigSettings.minApprovals);
        assertEq(_minConfirmations, multisigSettings.minConfirmations);
        assertEq(_emergencyMinApprovals, multisigSettings.emergencyMinApprovals);
        assertEq(_delayDuration, multisigSettings.delayDuration);
        assertEq(_memberOnlyProposalExecution, multisigSettings.memberOnlyProposalExecution);
        assertEq(_minExtraDuration, multisigSettings.minExtraDuration);
    }

    function test_members_list_limit_at_gas_limit() public {
        uint64 limit = type(uint16).max / 155;
        address[] memory _members = new address[](limit);
        for (uint256 i = 0; i < limit; i++) {
            _members[i] = address(uint160(i));
        }
        PolygonMultisigSetup _setup = new PolygonMultisigSetup();
        bytes memory _setupData = abi.encode(_members, multisigSettings);
        (, address _plugin) = createMockDaoWithPlugin(_setup, _setupData);
        assertEq(PolygonMultisig(_plugin).isMember(address(uint160(1))), true);
        assertEq(PolygonMultisig(_plugin).isMember(address(uint160(limit - 1))), true);
    }

    function test_interfaces() public {
        assertEq(plugin.supportsInterface(type(IMultisig).interfaceId), true);
        assertEq(plugin.supportsInterface(type(Addresslist).interfaceId), true);
        assertEq(plugin.supportsInterface(type(IMembership).interfaceId), true);
        assertEq(plugin.supportsInterface(type(IPlugin).interfaceId), true);
    }

    function test_reverts_if_reinitialized() public {
        super.setUp();
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(dao, members, multisigSettings);
    }

    function test_empty_members_list() public {
        PolygonMultisigSetup _setup = new PolygonMultisigSetup();
        bytes memory _setupData = abi.encode(new address[](0), multisigSettings);
        expectRevertCreateMockDaoWithPlugin(_setup, _setupData);
    }

    function test_empty_members_list_with_min_approvals_0() public {
        PolygonMultisigSetup _setup = new PolygonMultisigSetup();
        PolygonMultisig.MultisigSettings memory limitMultisigSettings = PolygonMultisig
            .MultisigSettings({
                onlyListed: true,
                minApprovals: 0,
                minConfirmations: 0,
                emergencyMinApprovals: 0,
                delayDuration: 0.5 days,
                memberOnlyProposalExecution: true,
                minExtraDuration: 0.5 days
            });

        bytes memory _setupData = abi.encode(new address[](0), limitMultisigSettings);
        expectRevertCreateMockDaoWithPlugin(_setup, _setupData);
    }
}

contract PolygonMultisigProposalCreationTest is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
    }

    function test_proposal_creation() public {
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        uint256 proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 1,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        assertEq(plugin.proposalCount(), 1);
        assertEq(
            proposalId,
            uint256(
                keccak256(abi.encode(address(0xB0b), bytes("ipfs://hello"), _actions, block.number))
            )
        );
        assertEq(plugin.getProposalIdByIndex(0), proposalId);
    }

    function test_voting_within_proposal_creation() public {
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        uint256 proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: true,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        assertEq(plugin.proposalCount(), 1);
        assertEq(plugin.hasApproved(proposalId, address(0xB0b)), true);
    }

    function test_reverts_if_not_member() public {
        vm.startPrank(address(0x0));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalCreationForbidden.selector, address(0x0))
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
    }

    // Test expect create proposal to fail if startDate is smaller than block.timestamp
    function test_reverts_if_start_date_smaller_than_block_timestamp() public {
        vm.prank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.DateOutOfBounds.selector,
                uint64(block.timestamp),
                uint64(block.timestamp - 1)
            )
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(block.timestamp - 1),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
    }

    // Test revert is startDate is greater than endDate
    function test_reverts_if_start_date_greater_than_end_date() public {
        vm.prank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.DateOutOfBounds.selector,
                uint64(block.timestamp + 1),
                uint64(block.timestamp)
            )
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(block.timestamp + 1),
            _endDate: uint64(block.timestamp),
            _emergency: false
        });
    }

    function test_reverts_if_start_date_out_of_bounds() public {
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.DateOutOfBounds.selector,
                uint64(block.timestamp),
                uint64(1)
            )
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(1),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
    }

    function test_reverts_if_end_date_out_of_bounds() public {
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.DateOutOfBounds.selector,
                uint64(block.timestamp),
                0
            )
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(0),
            _emergency: false
        });
    }

    function test_reverts_right_after_settings_change() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            minConfirmations: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 2,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        uint256 proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);
        (
            bool _onlyListed,
            uint16 _minApprovals,
            uint16 _minConfirmations,
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration,
            bool _memberOnlyProposalExecution,
            uint256 _minExtraDuration
        ) = plugin.multisigSettings();
        assertEq(_onlyListed, true);
        assertEq(_minApprovals, 2);
        assertEq(_minConfirmations, 2);
        assertEq(_emergencyMinApprovals, 2);
        assertEq(_delayDuration, 1 days);
        assertEq(_memberOnlyProposalExecution, false);
        assertEq(_minExtraDuration, 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ProposalCreationForbidden.selector,
                address(0xB0b)
            )
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
    }

    function test_different_proposal_creation_within_same_block() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        uint256 proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 1,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        plugin.createProposal({
            _metadata: bytes("ipfs://second-hello"),
            _actions: _actions,
            _allowFailureMap: 1,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        assertEq(plugin.proposalCount(), 2);
        assertEq(
            proposalId,
            uint256(
                keccak256(abi.encode(address(0xB0b), bytes("ipfs://hello"), _actions, block.number))
            )
        );
        assertEq(plugin.getProposalIdByIndex(0), proposalId);
    }

    function test_reverts_if_same_double_proposal_creation_within_same_block() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        uint256 proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 1,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ProposalCreationForbidden.selector,
                address(0xB0b)
            )
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 1,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        assertEq(plugin.proposalCount(), 1);
        assertEq(
            proposalId,
            uint256(
                keccak256(abi.encode(address(0xB0b), bytes("ipfs://hello"), _actions, block.number))
            )
        );
        assertEq(plugin.getProposalIdByIndex(0), proposalId);
    }

    function test_reverts_if_end_date_less_than_start_date_plus_delay_duration_and_min_extra_duration()
        public
    {
        vm.prank(address(0xB0b));

        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        vm.expectRevert();

        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 0.5 days + 0.2 days),
            _emergency: false
        });
    }
}

contract PolygonMultisigSecondaryMetadata is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
    }

    function test_secondary_metadata() public {
        vm.startPrank(address(0xB0b));
        assertEq(plugin.canApprove(proposalId, address(0xB0b)), true);
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposalByIndex(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
    }

    function test_set_secondary_metadata_after_delay_duration() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://universe"));
        plugin.startProposalDelay(proposalId);
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposalByIndex(0);
        assertEq(_secondaryMetadata, bytes("ipfs://universe"));
    }

    function test_delay_lasts_the_defined_amount() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposalByIndex(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));

        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), false);
        vm.warp(block.timestamp + 1 days);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), true);
    }

    function test_proposal_creation_at_edge_time() public {
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        plugin.createProposal({
            _metadata: bytes("ipfs://second-hello"),
            _actions: _actions,
            _allowFailureMap: 1,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 0.5 days + 0.5 days),
            _emergency: false
        });
    }

    function test_proposal_creation_fails_if_end_time_is_less_than_extra_delay() public {
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.DateOutOfBounds.selector,
                uint64(block.timestamp),
                uint64(block.timestamp + 1 days - 1)
            )
        );
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 1,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 0.5 days + 0.5 days - 1),
            _emergency: false
        });
    }

    function test_reverts_if_not_member() public {
        vm.prank(address(0xB0b));
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        vm.prank(address(0x0));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.NotInMemberList.selector, address(0x0))
        );
        plugin.startProposalDelay(proposalId);
    }

    function test_reverts_if_not_permissions() public {
        vm.expectRevert();
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
    }

    function test_reverts_if_delay_started_after_end_date() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.MetadataCantBeSet.selector));
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.DelayCantBeSet.selector));
        plugin.startProposalDelay(proposalId);
    }

    function test_reverts_if_not_enough_approvals() public {
        vm.startPrank(address(0xB0b));
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.InsuficientApprovals.selector, 0, 1)
        );
        plugin.startProposalDelay(proposalId);
    }

    function test_reverts_if_proposal_is_emergency() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        uint256 _secondProposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: true
        });
        plugin.approve(_secondProposalId);
        plugin.setSecondaryMetadata(_secondProposalId, bytes("ipfs://world"));
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.DelayCantBeSet.selector));
        plugin.startProposalDelay(_secondProposalId);
    }

    function test_reverts_if_attempting_to_start_delay_multiple_times() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposalByIndex(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
        vm.expectRevert();
        plugin.startProposalDelay(proposalId);
    }
}

contract PolygonMultisigEmergencyFlows is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: true
        });
    }

    // executes after a proposal has been approved
    function test_execute_proposal() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        assertEq(plugin.canExecute(proposalId), true);
        plugin.execute(proposalId);
        (bool _executed, , , , , , , , ) = plugin.getProposal(proposalId);
        assertEq(_executed, true);
    }

    function test_emergency_can_set_metadata_before() public {
        vm.startPrank(address(0xB0b));
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposalByIndex(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
    }

    function test_emergency_can_set_metadata_after() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposalByIndex(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
    }

    function test_reverts_if_setting_metadata_after_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        assertEq(plugin.canExecute(proposalId), true);
        plugin.execute(proposalId);
        (bool _executed, , , , , , , , ) = plugin.getProposal(proposalId);
        assertEq(_executed, true);
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.MetadataCantBeSet.selector));
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
    }

    function test_reverts_if_not_address_doesnt_have_permission_setting_metadata() public {
        vm.startPrank(address(0x0));
        vm.expectRevert();
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
    }

    function test_reverts_if_not_enough_approvals_in_emergency() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
    }

    function test_if_emergency_metadata_already_set() public {
        vm.startPrank(address(0xB0b));
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://hello"));
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposalByIndex(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
    }

    function test_revert_execute_proposal_when_no_member() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        assertEq(plugin.canExecute(proposalId), true);
        vm.stopPrank();
        vm.startPrank(address(0xdeaad));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
    }
}

contract PolygonMultisigEmergencyExtraMembersFlows is PolygonMultisigExtraMembersTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: true
        });
        vm.stopPrank();
    }

    // executes after a proposal has been approved
    function test_execute_proposal() public {
        vm.prank(address(0xB0b));
        plugin.approve(proposalId);
        vm.stopPrank();

        vm.prank(address(0xDead));
        plugin.approve(proposalId);
        vm.stopPrank();

        vm.prank(address(0xBeef));
        plugin.approve(proposalId);
        vm.stopPrank();

        plugin.execute(proposalId);
        (bool _executed, , , , , , , , ) = plugin.getProposal(proposalId);
        assertEq(_executed, true);
    }

    function test_reverts_if_not_enough_approvals_in_emergency() public {
        vm.prank(address(0xB0b));
        plugin.approve(proposalId);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
        vm.stopPrank();

        vm.prank(address(0xDead));
        plugin.approve(proposalId);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
    }
}

contract PolygonMultisigApprovals is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: true
        });
    }

    function test_approval() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        (, uint16 _approvals, , , , , , , ) = plugin.getProposalByIndex(0);
        assertEq(_approvals, uint16(1));
    }

    function test_approve_proposal_at_start() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        uint256 secondProp = plugin.createProposal({
            _metadata: bytes("ipfs://second-hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(block.timestamp + 1 days),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
        vm.warp(block.timestamp + 1 days);
        plugin.approve(secondProp);
        (, uint16 _approvals, , , , , , , ) = plugin.getProposalByIndex(1);
        assertEq(_approvals, uint16(1));
    }

    function test_reverts_if_not_member() public {
        vm.startPrank(address(0x0));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                proposalId,
                address(0x0)
            )
        );
        plugin.approve(proposalId);
    }

    function test_reverts_if_already_approved() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.approve(proposalId);
    }

    function test_reverts_if_proposal_already_executed() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);

        plugin.execute(proposalId);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.approve(proposalId);
    }

    function test_reverts_if_proposal_already_executed_by_another_account() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);

        plugin.execute(proposalId);
        vm.stopPrank();
        vm.startPrank(address(0xdeaf));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                proposalId,
                address(0xdeaf)
            )
        );
        plugin.approve(proposalId);
    }

    function test_reverts_if_proposal_delay_already_started() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        uint256 secondProp = plugin.createProposal({
            _metadata: bytes("ipfs://second-hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
        plugin.approve(secondProp);
        plugin.setSecondaryMetadata(secondProp, bytes("ipfs://world"));
        plugin.startProposalDelay(secondProp);
        vm.stopPrank();
        vm.startPrank(address(0xdeaf));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                secondProp,
                address(0xdeaf)
            )
        );
        plugin.approve(secondProp);
    }

    function test_reverts_if_proposal_ended() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        uint256 secondProp = plugin.createProposal({
            _metadata: bytes("ipfs://second-hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                secondProp,
                address(0xB0b)
            )
        );
        plugin.approve(secondProp);
    }
}

contract PolygonMultisigConfirmations is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
    }

    function test_confirmation() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), true);
        plugin.confirm(proposalId);
        (, , , , , uint16 _confirmations, , , ) = plugin.getProposalByIndex(0);
        assertEq(_confirmations, uint16(1));
    }

    function test_with_higher_confirmations() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            minConfirmations: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 2,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);

        assertEq(plugin.isMember(address(0xB0b)), true);
        vm.roll(block.number + 1);

        _actions = new IDAO.Action[](0);
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), true);
        plugin.confirm(proposalId);
        (, , , , , uint16 _confirmations, , , ) = plugin.getProposalByIndex(2);
        assertEq(_confirmations, uint16(1));
        vm.stopPrank();

        vm.startPrank(address(0xdeaf));
        plugin.confirm(proposalId);
        (, , , , , uint16 _confirmations2, , , ) = plugin.getProposalByIndex(2);
        assertEq(_confirmations2, uint16(2));
    }

    function test_reverts_confirmations_too_small() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            minConfirmations: 0,
            delayDuration: 1 days,
            emergencyMinApprovals: 2,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }

    function test_reverts_if_double_confirmation() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(proposalId);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.confirm(proposalId);
    }

    function test_reverts_confirmation_if_late_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 2 days);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.confirm(proposalId);
    }

    function test_reverts_confirmation_if_too_early() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration - 1);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.confirm(proposalId);
    }

    function test_reverts_confirmation_if_no_member() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        vm.startPrank(address(0xDad));
        assertEq(plugin.canConfirm(proposalId, address(0xDad)), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xDad)
            )
        );
        plugin.confirm(proposalId);
    }

    function test_reverts_confirmation_if_proposal_not_approved() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.confirm(proposalId);
    }

    function test_reverts_confirmation_if_proposal_already_executed() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);
        vm.stopPrank();
        vm.startPrank(address(0xdeaf));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xdeaf)
            )
        );
        plugin.confirm(proposalId);
    }

    function test_reverts_confirmation_if_proposal_delay_not_started() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.confirm(proposalId);
    }

    function test_reverts_confirmation_if_proposal_delay_not_ended() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        vm.warp(block.timestamp + 0.5 days - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                proposalId,
                address(0xB0b)
            )
        );
        plugin.confirm(proposalId);
    }
}

contract PolygonMultisigExecution is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
    }

    function test_confirmation_and_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), true);
        plugin.confirm(proposalId);
        (, , , , , uint16 _confirmations, , , ) = plugin.getProposalByIndex(0);
        assertEq(_confirmations, uint16(1));
        plugin.execute(proposalId);
        (bool _executed, , , , , , , , ) = plugin.getProposalByIndex(0);
        assertEq(_executed, true);
    }

    // executes after a proposal has been approved
    function test_revert_execute_proposal_after_approving() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
    }

    function test_reverts_if_not_enough_approvals() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
    }

    function test_reverts_if_not_enough_confirmations() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), true);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
    }

    function test_reverts_confirmation_and_late_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(proposalId, address(0xB0b)), true);
        plugin.confirm(proposalId);
        (, , , , , uint16 _confirmations, , , ) = plugin.getProposalByIndex(0);
        assertEq(_confirmations, uint16(1));
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute(proposalId);
    }
}

contract PolygonMultisigGettersTest is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
    }

    function test_proposal_getter() public {
        (
            bool _executed,
            uint16 _approvals,
            PolygonMultisig.ProposalParameters memory _parameters,
            IDAO.Action[] memory _actions,
            uint256 _allowFailureMap,
            uint16 _confirmations,
            bytes memory _metadata,
            bytes memory _secondaryMetadata,
            uint64 _firstDelayStartBlock
        ) = plugin.getProposalByIndex(0);
        assertEq(_executed, false);
        assertEq(_approvals, 0);
        assertEq(_parameters.minApprovals, uint64(1));
        assertEq(_parameters.snapshotBlock, uint64(block.number - 1));
        assertEq(_parameters.startDate, uint64(block.timestamp));
        assertEq(_parameters.endDate, uint64(block.timestamp + 1 days));
        assertEq(_parameters.delayDuration, uint64(0.5 days));
        assertEq(_parameters.emergency, false);
        assertEq(_parameters.emergencyMinApprovals, 1);
        assertEq(_parameters.memberOnlyProposalExecution, true);
        assertEq(_actions.length, 1);
        assertEq(_allowFailureMap, 0);
        assertEq(_confirmations, 0);
        assertEq(_metadata, bytes("ipfs://hello"));
        assertEq(_secondaryMetadata, bytes(""));
        assertEq(_firstDelayStartBlock, 0);
    }
}

contract PolygonMultisigChangeMembersTest is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
    }

    function test_add_multisig_members() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        address[] memory _addresses = new address[](1);
        _addresses[0] = address(0xa11ce);

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.addAddresses, _addresses)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);

        assert(plugin.isMember(address(0xa11ce)));
    }

    function test_remove_multisig_members() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        address[] memory _addresses = new address[](1);
        _addresses[0] = address(0xB0b);

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.removeAddresses, _addresses)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);

        assertEq(plugin.isMember(address(0xB0b)), false);
    }

    function test_reverts_if_removals_are_lower_than_min_emergency_approvals() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        address[] memory _addresses = new address[](2);
        _addresses[0] = address(0xB0b);
        _addresses[1] = address(0xdeaf);

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.removeAddresses, _addresses)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }

    function test_reverts_if_removals_are_lower_than_min_approvals() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        address[] memory _addresses = new address[](2);
        _addresses[0] = address(0xB0b);
        _addresses[1] = address(0xdeaf);

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.removeAddresses, _addresses)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delayDuration, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }
}

contract PolygonMultisigChangeSettingsTest is PolygonMultisigTest {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();
    }

    function test_change_min_approvals() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            minConfirmations: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 2,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);
        (
            bool _onlyListed,
            uint16 _minApprovals,
            uint16 _minConfirmations,
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration,
            bool _memberOnlyProposalExecution,
            uint256 _minExtraDuration
        ) = plugin.multisigSettings();
        assertEq(_onlyListed, true);
        assertEq(_minApprovals, 2);
        assertEq(_minConfirmations, 2);
        assertEq(_emergencyMinApprovals, 2);
        assertEq(_delayDuration, 1 days);
        assertEq(_memberOnlyProposalExecution, false);
        assertEq(_minExtraDuration, 1 days);
    }

    function test_reverts_if_min_approvals_is_zero() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 0,
            minConfirmations: 0,
            delayDuration: 1 days,
            emergencyMinApprovals: 1,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }

    function test_reverts_if_emergency_min_approvals_is_zero() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            minConfirmations: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 0,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }

    function test_reverts_if_min_approvals_is_higher_than_members() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            minConfirmations: 3,
            delayDuration: 1 days,
            emergencyMinApprovals: 1,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }

    function test_reverts_if_emergency_min_approvals_is_higher_than_members() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            minConfirmations: 1,
            delayDuration: 1 days,
            emergencyMinApprovals: 3,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }

    function test_reverts_if_emergency_min_approvals_is_smaller_than_min_approvals() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            minConfirmations: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 1,
            memberOnlyProposalExecution: false,
            minExtraDuration: 1 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        vm.expectRevert();
        plugin.execute(proposalId);
    }

    function test_change_min_extra_duration() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            minConfirmations: 1,
            emergencyMinApprovals: 1,
            delayDuration: 0.5 days,
            memberOnlyProposalExecution: true,
            minExtraDuration: 5 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);
        (
            bool _onlyListed,
            uint16 _minApprovals,
            uint16 _minConfirmations,
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration,
            bool _memberOnlyProposalExecution,
            uint256 _minExtraDuration
        ) = plugin.multisigSettings();

        assertEq(_onlyListed, true);
        assertEq(_minApprovals, 1);
        assertEq(_minConfirmations, 1);
        assertEq(_emergencyMinApprovals, 1);
        assertEq(_delayDuration, 0.5 days);
        assertEq(_memberOnlyProposalExecution, true);
        assertEq(_minExtraDuration, 5 days);
    }

    function test_remove_min_extra_duration_by_setting_to_zero() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            minConfirmations: 1,
            emergencyMinApprovals: 1,
            delayDuration: 0.5 days,
            memberOnlyProposalExecution: true,
            minExtraDuration: 0 days
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        proposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(proposalId);
        plugin.setSecondaryMetadata(proposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(proposalId);
        (, , , , uint64 _delay, , ) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(proposalId);
        plugin.execute(proposalId);
        (
            bool _onlyListed,
            uint16 _minApprovals,
            uint16 _minConfirmations,
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration,
            bool _memberOnlyProposalExecution,
            uint256 _minExtraDuration
        ) = plugin.multisigSettings();

        assertEq(_onlyListed, true);
        assertEq(_minApprovals, 1);
        assertEq(_minConfirmations, 1);
        assertEq(_emergencyMinApprovals, 1);
        assertEq(_delayDuration, 0.5 days);
        assertEq(_memberOnlyProposalExecution, true);
        assertEq(_minExtraDuration, 0 days);
    }
}

contract PolygonMultisigIsListedEdgesTest is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
    }

    function test_fail_adding_secondary_metadata_when_not_in_right_block() public {
        address intruder = address(0xdead);
        address[] memory intruders = new address[](1);
        intruders[0] = intruder;
        // Creating the first proposal to add the intruder
        uint256 intruderProposalId = super.addMemberToPluginWithoutExecution(intruders);

        vm.startPrank(address(0xB0b));
        // Creating the second proposal to test the intruder execution permissions
        uint256 secondProposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: new IDAO.Action[](0),
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });

        // Passing the first proposal to add the intruder
        plugin.execute(intruderProposalId);

        // Taking the second proposal to the last stage
        plugin.approve(secondProposalId);

        plugin.setSecondaryMetadata(secondProposalId, bytes("ipfs://world"));
        vm.stopPrank();
        vm.startPrank(intruder);
        vm.expectRevert();
        plugin.startProposalDelay(secondProposalId);

        vm.stopPrank();
        vm.startPrank(address(0xB0b));
        plugin.setSecondaryMetadata(secondProposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(secondProposalId);
    }

    function test_fail_executing_when_member_not_in_right_block() public {
        address intruder = address(0xdead);
        address[] memory intruders = new address[](1);
        intruders[0] = intruder;
        // Creating the first proposal to add the intruder
        uint256 intruderProposalId = super.addMemberToPluginWithoutExecution(intruders);

        vm.startPrank(address(0xB0b));
        // Creating the second proposal to test the intruder execution permissions
        uint256 secondProposalId = plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: new IDAO.Action[](0),
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });

        // Passing the first proposal to add the intruder
        plugin.execute(intruderProposalId);

        // Taking the second proposal to the last stage
        plugin.approve(secondProposalId);
        plugin.setSecondaryMetadata(secondProposalId, bytes("ipfs://world"));
        plugin.startProposalDelay(secondProposalId);
        plugin.multisigSettings();
        vm.warp(block.timestamp + 1 days);
        plugin.confirm(secondProposalId);
        vm.stopPrank();

        vm.startPrank(intruder);
        assertTrue(plugin.isMember(intruder) == true, "should be member");
        // Executer is member, but was not included in the block where the proposal was created
        vm.expectRevert();
        plugin.execute(secondProposalId);
        vm.stopPrank();

        vm.startPrank(address(0xB0b));
        plugin.execute(secondProposalId);

        (bool _executed, , , , , , , , ) = plugin.getProposal(secondProposalId);
        assertEq(_executed, true);
    }
}
