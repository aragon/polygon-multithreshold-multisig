// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {AragonTest} from "./base/AragonTest.sol";
import {PolygonMultisigSetup} from "../src/PolygonMultisigSetup.sol";
import {PolygonMultisig} from "../src/PolygonMultisig.sol";

abstract contract PolygonMultisigTest is AragonTest {
    DAO internal dao;
    PolygonMultisig internal plugin;
    PolygonMultisigSetup internal setup;
    address[] members = [address(0xB0b)];
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
        // vm.warp(1);
    }
}

contract PolygonMultisigInitializeTest is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize() public {
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

    function test_reverts_if_reinitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(dao, members, multisigSettings);
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
            _allowFailureMap: 0,
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
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        (, , , , , , , bytes memory _secondaryMetadata, ) = plugin.getProposal(0);
        assertEq(_secondaryMetadata, bytes("ipfs://world"));
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
        vm.expectRevert(PolygonMultisig.DelayAlreadyStarted.selector);
        plugin.startProposalDelay(0, bytes("ipfs://failure"));
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
        plugin.execute(0);
        (bool _executed, , , , , , , , ) = plugin.getProposal(0);
        assertEq(_executed, true);
    }

    function test_reverts_if_not_enough_approvals_in_emergency() public {
        vm.startPrank(address(0xB0b));
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }
}
contract PolygonMultisigConfirmation is PolygonMultisigTest {
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
        ( , , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
        plugin.confirm(0);
        ( , , , , , uint16 _confirmations, , , ) = plugin.getProposal(0);
        assertEq(_confirmations, uint16(1));
    }

    function test_reverts_confirmation_if_late_execution() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        ( , , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 2 days);
        assertEq(plugin.canConfirm(0, address(0xB0b)), false);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ConfirmationCastForbidden.selector, 0, address(0xB0b))
        );
        plugin.confirm(0);
    }
    function test_reverts_confirmation_if_no_member() public {
        vm.startPrank(address(0xB0b));
        plugin.approve(0);
        plugin.startProposalDelay(0, bytes("ipfs://world"));
        ( , , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        vm.startPrank(address(0xDad));
        assertEq(plugin.canConfirm(0, address(0xDad)), false);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ConfirmationCastForbidden.selector, 0, address(0xDad))
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
        ( , , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
        plugin.confirm(0);
        ( , , , , , uint16 _confirmations, , , ) = plugin.getProposal(0);
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
        ( , , , uint64 _delayDuration) = plugin.multisigSettings();
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
        ( , , , uint64 _delayDuration) = plugin.multisigSettings();
        vm.warp(block.timestamp + _delayDuration + 1);
        assertEq(plugin.canConfirm(0, address(0xB0b)), true);
        plugin.confirm(0);
        ( , , , , , uint16 _confirmations, , , ) = plugin.getProposal(0);
        assertEq(_confirmations, uint16(1));
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(PolygonMultisig.ProposalExecutionForbidden.selector, 0)
        );
        plugin.execute(0);
    }
}
