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
            emergencyMinApprovals: 1,
            delayDuration: 1 days
        });

    function setUp() public virtual {
        vm.prank(address(0xB0b));
        setup = new PolygonMultisigSetup();
        bytes memory setupData = abi.encode(members, multisigSettings);

        (DAO _dao, address _plugin) = createMockDaoWithPlugin(setup, setupData);

        dao = _dao;
        plugin = PolygonMultisig(_plugin);
        vm.roll(block.number + 1);
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
            emergencyMinApprovals: 3,
            delayDuration: 1 days
        });

    function setUp() public virtual {
        vm.prank(address(0xB0b));
        setup = new PolygonMultisigSetup();
        bytes memory setupData = abi.encode(members, multisigSettings);

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
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration
        ) = plugin.multisigSettings();
        assertEq(_onlyListed, multisigSettings.onlyListed);
        assertEq(_minApprovals, multisigSettings.minApprovals);
        assertEq(_emergencyMinApprovals, multisigSettings.emergencyMinApprovals);
        assertEq(_delayDuration, multisigSettings.delayDuration);
    }

    function test_members_list_limit() public {
        address[] memory _members = new address[](type(uint16).max);
        for (uint256 i = 0; i < type(uint16).max; i++) {
            _members[i] = address(uint160(i));
        }
        PolygonMultisigSetup _setup = new PolygonMultisigSetup();
        bytes memory _setupData = abi.encode(_members, multisigSettings);
        (DAO _dao, address _plugin) = createMockDaoWithPlugin(_setup, _setupData);
        assertEq(PolygonMultisig(_plugin).isMember(address(uint160(1))), true);
        assertEq(PolygonMultisig(_plugin).isMember(address(uint160(type(uint16).max - 1))), true);
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
}

contract PolygonMultisigProposalCreationLimitTest is AragonTest {
    DAO internal dao;
    PolygonMultisig internal plugin;
    PolygonMultisigSetup internal setup;
    address[] members = new address[](65536);
    PolygonMultisig.MultisigSettings multisigSettings =
        PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            emergencyMinApprovals: 1,
            delayDuration: 1 days
        });

    function test_reverts_members_list_limit() public {
        PolygonMultisigSetup _setup = new PolygonMultisigSetup();
        bytes memory _setupData = abi.encode(members, multisigSettings);

        DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), EMPTY_BYTES)));
        _dao.initialize(EMPTY_BYTES, address(this), address(0), "");
        vm.expectRevert();
        (address plugin, PluginSetup.PreparedSetupData memory preparedSetupData) = _setup
            .prepareInstallation(address(_dao), _setupData);
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
    }

    function test_voting_within_proposal_creation() public {
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: true,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: false
        });
        assertEq(plugin.proposalCount(), 1);
        assertEq(plugin.hasApproved(0, address(0xB0b)), true);
    }

    function test_reverts_if_not_member() public {
        vm.prank(address(0x0));
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
            delayDuration: 1 days,
            emergencyMinApprovals: 2
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delay) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(0);
        plugin.execute(0);
        (
            bool _onlyListed,
            uint16 _minApprovals,
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration
        ) = plugin.multisigSettings();
        assertEq(_onlyListed, true);
        assertEq(_minApprovals, 2);
        assertEq(_emergencyMinApprovals, 2);
        assertEq(_delayDuration, 1 days);

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
}

contract PolygonMultisigSecondaryMetadata is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
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

    function test_secondary_metadata() public {
        vm.startPrank(address(0xB0b));
        assertEq(plugin.canApprove(0, address(0xB0b)), true);
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposal(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
    }

    function test_delay_lasts_the_defined_amount() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposal(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));

        assertEq(plugin.canConfirm(0, address(0xB0b)), false);
        vm.warp(block.timestamp + 1 days);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
    }

    function test_reverts_if_not_member() public {
        vm.prank(address(0x0));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.NotInMemberList.selector, address(0x0))
        );
        plugin.startProposalDelay(0, bytes("ipfs://world"));
    }

    function test_reverts_if_metadata_was_already_set() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        vm.expectRevert(PolygonMultisig.MetadataCantBeSet.selector);
        plugin.startProposalDelay(0, bytes("ipfs://failure"));
    }

    function test_reverts_if_delay_started_after_end_date() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.MetadataCantBeSet.selector));
        plugin.startProposalDelay(0, bytes("ipfs://world"));
    }

    function test_reverts_if_emergency_metadata_called() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.MetadataCantBeSet.selector));
        plugin.setEmergencySecondaryMetadata(0, bytes("ipfs://world"));
    }

    function test_reverts_if_not_enough_approvals() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.InsuficientApprovals.selector, 0, 1)
        );
        plugin.startProposalDelay(0, bytes("ipfs://world"));
    }

    function test_reverts_if_proposal_is_emergency() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 1 days),
            _emergency: true
        });
        plugin.approve(1);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.EmergencyProposalCantBeDelayed.selector)
        );
        plugin.startProposalDelay(1, bytes("ipfs://world"));
    }
}

contract PolygonMultisigEmergencyFlows is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        plugin.createProposal({
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
        plugin.approve(0);
        assertEq(plugin.canExecute(0), true);
        plugin.execute(0);
        (bool _executed, , , , , , , , ) = plugin.getProposal(0);
        assertEq(_executed, true);
    }

    function test_emergency_can_set_metadata_before() public {
        vm.startPrank(address(0xB0b));
        plugin.setEmergencySecondaryMetadata(0, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposal(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
    }

    function test_emergency_can_set_metadata_after() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.setEmergencySecondaryMetadata(0, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposal(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
    }

    function test_reverts_if_not_enough_approvals_in_emergency() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }

    function test_reverts_if_emergency_metadata_after_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.execute(0);
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.MetadataCantBeSet.selector));
        plugin.setEmergencySecondaryMetadata(0, bytes("ipfs://world"));
    }

    function test_reverts_if_emergency_metadata_already_set() public {
        vm.startPrank(address(0xB0b));
        plugin.setEmergencySecondaryMetadata(0, bytes("ipfs://world"));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.SecondaryMetadataAlreadySet.selector)
        );
        plugin.setEmergencySecondaryMetadata(0, bytes("ipfs://world"));
    }

    function test_reverts_if_emergency_metadata_after_delay() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert(abi.encodeWithSelector(PolygonMultisig.MetadataCantBeSet.selector));
        plugin.setEmergencySecondaryMetadata(0, bytes("ipfs://world"));
    }
}

contract PolygonMultisigEmergencyExtraMembersFlows is PolygonMultisigExtraMembersTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        plugin.createProposal({
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
        plugin.approve(0);
        vm.stopPrank();

        vm.prank(address(0xDead));
        plugin.approve(0);
        vm.stopPrank();

        vm.prank(address(0xBeef));
        plugin.approve(0);
        vm.stopPrank();

        plugin.execute(0);
        (bool _executed, , , , , , , , ) = plugin.getProposal(0);
        assertEq(_executed, true);
    }

    function test_reverts_if_not_enough_approvals_in_emergency() public {
        vm.prank(address(0xB0b));
        plugin.approve(0);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
        vm.stopPrank();

        vm.prank(address(0xDead));
        plugin.approve(0);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }
}

contract PolygonMultisigApprovals is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        plugin.createProposal({
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
        plugin.approve(0);
        (, uint16 _approvals, , , , , , , ) = plugin.getProposal(0);
        assertEq(_approvals, uint16(1));
    }

    function test_approve_proposal_at_start() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(block.timestamp + 1 days),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
        vm.warp(block.timestamp + 1 days);
        plugin.approve(1);
        (, uint16 _approvals, , , , , , , ) = plugin.getProposal(1);
        assertEq(_approvals, uint16(1));
    }

    function test_reverts_if_not_member() public {
        vm.startPrank(address(0x0));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ApprovalCastForbidden.selector, 0, address(0x0))
        );
        plugin.approve(0);
    }

    function test_reverts_if_already_approved() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.approve(0);
    }

    function test_reverts_if_proposal_already_executed() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);

        plugin.execute(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.approve(0);
    }

    function test_reverts_if_proposal_already_executed_by_another_account() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);

        plugin.execute(0);
        vm.stopPrank();
        vm.startPrank(address(0xdeaf));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                0,
                address(0xdeaf)
            )
        );
        plugin.approve(0);
    }

    function test_reverts_if_proposal_delay_already_started() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });
        plugin.approve(1);
        plugin.startProposalDelay(1, bytes("ipfs://world"));
        vm.stopPrank();
        vm.startPrank(address(0xdeaf));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ApprovalCastForbidden.selector,
                1,
                address(0xdeaf)
            )
        );
        plugin.approve(1);
    }

    function test_reverts_if_proposal_ended() public {
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
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
                1,
                address(0xB0b)
            )
        );
        plugin.approve(1);
    }
}

contract PolygonMultisigConfirmations is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
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

    function test_confirmation() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
        plugin.confirm(0);
        (, , , , , uint16 _confirmations, , , ) = plugin.getProposal(0);
        assertEq(_confirmations, uint16(1));
    }

    function test_reverts_if_double_confirmation() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.confirm(0);
    }

    function test_reverts_confirmation_if_late_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 2 days);
        assertEq(plugin.canConfirm(0, address(0xB0b)), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.confirm(0);
    }

    function test_reverts_confirmation_if_too_early() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration - 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.confirm(0);
    }

    function test_reverts_confirmation_if_no_member() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        vm.startPrank(address(0xDad));
        assertEq(plugin.canConfirm(0, address(0xDad)), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xDad)
            )
        );
        plugin.confirm(0);
    }

    function test_reverts_confirmation_if_proposal_not_approved() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.confirm(0);
    }

    function test_reverts_confirmation_if_proposal_already_executed() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(0);
        plugin.execute(0);
        vm.stopPrank();
        vm.startPrank(address(0xdeaf));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xdeaf)
            )
        );
        plugin.confirm(0);
    }

    function test_reverts_confirmation_if_proposal_delay_not_started() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.confirm(0);
    }

    function test_reverts_confirmation_if_proposal_delay_not_ended() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        vm.warp(block.timestamp + 1 days - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolygonMultisig.ConfirmationCastForbidden.selector,
                0,
                address(0xB0b)
            )
        );
        plugin.confirm(0);
    }
}

contract PolygonMultisigExecution is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(address(0xB0b));
        IDAO.Action[] memory _actions = new IDAO.Action[](0);
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

    function test_confirmation_and_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
        plugin.confirm(0);
        (, , , , , uint16 _confirmations, , , ) = plugin.getProposal(0);
        assertEq(_confirmations, uint16(1));
        plugin.execute(0);
        (bool _executed, , , , , , , , ) = plugin.getProposal(0);
        assertEq(_executed, true);
    }

    // executes after a proposal has been approved
    function test_revert_execute_proposal_after_approving() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }

    function test_reverts_if_not_enough_approvals() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }

    function test_reverts_if_not_enough_confirmations() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }

    function test_reverts_confirmation_and_late_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
        plugin.confirm(0);
        (, , , , , uint16 _confirmations, , , ) = plugin.getProposal(0);
        assertEq(_confirmations, uint16(1));
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }
}

contract PolygonMultisigGettersTest is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
        vm.prank(address(0xB0b));
        IDAO.Action memory _action = IDAO.Action({to: address(0x0), value: 0, data: bytes("0x00")});
        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = _action;
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
        ) = plugin.getProposal(0);

        assertEq(_executed, false);
        assertEq(_approvals, 0);
        assertEq(_parameters.minApprovals, uint64(1));
        assertEq(_parameters.snapshotBlock, uint64(block.number - 1));
        assertEq(_parameters.startDate, uint64(block.timestamp));
        assertEq(_parameters.endDate, uint64(block.timestamp + 1 days));
        assertEq(_parameters.delayDuration, uint64(1 days));
        assertEq(_parameters.emergency, false);
        assertEq(_parameters.emergencyMinApprovals, 1);
        assertEq(_actions.length, 1);
        assertEq(_allowFailureMap, 0);
        assertEq(_confirmations, 0);
        assertEq(_metadata, bytes("ipfs://hello"));
        assertEq(_secondaryMetadata, bytes(""));
        assertEq(_firstDelayStartBlock, 0);
    }
}

contract PolygonMultisigChangeMembersTest is PolygonMultisigTest {
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
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(0);
        plugin.execute(0);

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
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(0);
        plugin.execute(0);

        assertEq(plugin.isMember(address(0xB0b)), false);
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
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(0);
        vm.expectRevert();
        plugin.execute(0);
    }

    function test_reverts_if_adding_too_many_members() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        address[] memory _addresses = new address[](type(uint16).max);
        for (uint256 i = 0; i < type(uint16).max; i++) {
            _addresses[i] = address(uint160(i));
        }

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.addAddresses, _addresses)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        plugin.confirm(0);
        vm.expectRevert();
        plugin.execute(0);
    }
}

contract PolygonMultisigChangeSettingsTest is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
    }

    function test_change_min_approvals() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 2
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delay) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(0);
        plugin.execute(0);
        (
            bool _onlyListed,
            uint16 _minApprovals,
            uint16 _emergencyMinApprovals,
            uint64 _delayDuration
        ) = plugin.multisigSettings();
        assertEq(_onlyListed, true);
        assertEq(_minApprovals, 2);
        assertEq(_emergencyMinApprovals, 2);
        assertEq(_delayDuration, 1 days);
    }

    function test_reverts_if_min_approvals_is_zero() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 0,
            delayDuration: 1 days,
            emergencyMinApprovals: 1
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delay) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(0);
        vm.expectRevert();
        plugin.execute(0);
    }

    function test_reverts_if_emergency_min_approvals_is_zero() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 0
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delay) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(0);
        vm.expectRevert();
        plugin.execute(0);
    }

    function test_reverts_if_min_approvals_is_higher_than_members() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            delayDuration: 1 days,
            emergencyMinApprovals: 1
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delay) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(0);
        vm.expectRevert();
        plugin.execute(0);
    }

    function test_reverts_if_emergency_min_approvals_is_higher_than_members() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            delayDuration: 1 days,
            emergencyMinApprovals: 3
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delay) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(0);
        vm.expectRevert();
        plugin.execute(0);
    }

    function test_reverts_if_emergency_min_approvals_is_smaller_than_min_approvals() public {
        IDAO.Action[] memory _actions = new IDAO.Action[](1);

        PolygonMultisig.MultisigSettings memory _settings = PolygonMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            delayDuration: 1 days,
            emergencyMinApprovals: 1
        });

        _actions[0] = IDAO.Action({
            to: address(plugin),
            value: 0,
            data: abi.encodeCall(PolygonMultisig.updateMultisigSettings, _settings)
        });

        vm.startPrank(address(0xB0b));
        plugin.createProposal({
            _metadata: bytes("ipfs://hello"),
            _actions: _actions,
            _allowFailureMap: 0,
            _approveProposal: false,
            _startDate: uint64(0),
            _endDate: uint64(block.timestamp + 2 days),
            _emergency: false
        });

        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , uint64 _delay) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delay + 1);
        plugin.confirm(0);
        vm.expectRevert();
        plugin.execute(0);
    }
}
