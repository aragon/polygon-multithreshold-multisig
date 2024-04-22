// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.24;

import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PolygonMultisig} from "./PolygonMultisig.sol";

/// @title PolygonMultisigSetup build 1
contract PolygonMultisigSetup is PluginSetup {
    address private immutable IMPLEMEMTATION;

    constructor() {
        IMPLEMEMTATION = address(new PolygonMultisig());
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes memory _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        (address[] memory members, PolygonMultisig.MultisigSettings memory multisigSettings) = abi
            .decode(_data, (address[], PolygonMultisig.MultisigSettings));

        plugin = createERC1967Proxy(
            IMPLEMEMTATION,
            abi.encodeCall(PolygonMultisig.initialize, (IDAO(_dao), members, multisigSettings))
        );

        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](1);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: keccak256("STORE_PERMISSION")
        });

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external pure returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = new PermissionLib.MultiTargetPermission[](1);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: keccak256("STORE_PERMISSION")
        });
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view returns (address) {
        return IMPLEMEMTATION;
    }
}
