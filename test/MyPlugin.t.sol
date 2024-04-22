// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

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
        PolygonMultisig.MultisigSettings({onlyListed: true, minApprovals: 1});

    function setUp() public virtual {
        setup = new PolygonMultisigSetup();
        bytes memory setupData = abi.encode(members, multisigSettings);

        (DAO _dao, address _plugin) = createMockDaoWithPlugin(setup, setupData);

        dao = _dao;
        plugin = PolygonMultisig(_plugin);
    }
}

contract PolygonMultisigInitializeTest is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize() public {
        assertEq(address(plugin.dao()), address(dao));
        // TODO: Check the members are right
        // TODO: Check the multisigSettings are right
    }

    function test_reverts_if_reinitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(dao, members, multisigSettings);
    }
}

contract PolygonMultisigMembersTest is PolygonMultisigTest {
    function setUp() public override {
        super.setUp();
    }
}
