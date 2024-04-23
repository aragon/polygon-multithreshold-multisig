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

    function test_createProposal() public {
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
