// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {PolygonMultisig} from "../src/PolygonMultisig.sol";
import {PolygonMultisigSetup} from "../src/PolygonMultisigSetup.sol";

contract PolygonMultisigScript is Script {
    address pluginRepoFactory;
    DAOFactory daoFactory;
    string nameWithEntropy;
    address[] pluginAddress;
    address secondaryMetadataAdmin;

    // Deployment Parameters
    bool onlyListed;
    uint16 minApprovals;
    uint16 minConfirmations;
    uint16 emergencyMinApprovals;
    uint64 delayDuration;
    bool memberOnlyProposalExecution;
    uint256 minExtraDuration;

    function setUp() public {
        pluginRepoFactory = vm.envAddress("PLUGIN_REPO_FACTORY");
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
        nameWithEntropy = vm.envOr("NAME_WITH_ENTROPY", string.concat("polygon-multisig-", vm.toString(block.timestamp)));
        secondaryMetadataAdmin = vm.envAddress("SECONDARY_METADATA_ADMIN");

        // Deployment Plugin Parameters
        onlyListed = vm.envBool("ONLY_LISTED");
        minApprovals = uint16(vm.envUint("MIN_APPROVALS"));
        minConfirmations = uint16(vm.envUint("MIN_CONFIRMATIONS"));
        emergencyMinApprovals = uint16(vm.envUint("EMERGENCY_MIN_APPROVALS"));
        delayDuration = uint64(vm.envUint("DELAY_DURATION"));
        memberOnlyProposalExecution = vm.envBool("MEMBER_ONLY_PROPOSAL_EXECUTION");
        minExtraDuration = vm.envUint("MIN_EXTRA_DURATION");
    }

    function run() public {
        // 0. Setting up Foundry
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1. Deploying the Plugin Setup
        PolygonMultisigSetup pluginSetup = deployPluginSetup();

        // 2. Publishing it in the Aragon OSx Protocol
        PluginRepo pluginRepo = deployPluginRepo(address(pluginSetup));

        // 3. Defining the DAO Settings
        DAOFactory.DAOSettings memory daoSettings = getDAOSettings();

        // 4. Defining the plugin settings
        DAOFactory.PluginSettings[] memory pluginSettings = getPluginSettings(pluginRepo);

        // 5. Deploying the DAO
        vm.recordLogs();
        address createdDAO = address(daoFactory.createDao(daoSettings, pluginSettings));

        // 6. Getting the Plugin Address
        Vm.Log[] memory logEntries = vm.getRecordedLogs();

        for (uint256 i = 0; i < logEntries.length; i++) {
            if (
                logEntries[i].topics[0] ==
                keccak256("InstallationApplied(address,address,bytes32,bytes32)")
            ) {
                pluginAddress.push(address(uint160(uint256(logEntries[i].topics[2]))));
            }
        }

        vm.stopBroadcast();

        // 7. Logging the resulting addresses
        console2.log("Plugin Setup: ", address(pluginSetup));
        console2.log("Plugin Repo: ", address(pluginRepo));
        console2.log("Created DAO: ", address(createdDAO));
        console2.log("Installed Plugins: ");
        for (uint256 i = 0; i < pluginAddress.length; i++) {
            console2.log("- ", pluginAddress[i]);
        }
    }

    function deployPluginSetup() public returns (PolygonMultisigSetup) {
        PolygonMultisigSetup pluginSetup = new PolygonMultisigSetup();
        return pluginSetup;
    }

    function deployPluginRepo(address pluginSetup) public returns (PluginRepo pluginRepo) {
        pluginRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepoWithFirstVersion(
            nameWithEntropy,
            pluginSetup,
            msg.sender,
            "0x00", // TODO: Give these actual values on prod
            "0x00"
        );
    }

    function getDAOSettings() public view returns (DAOFactory.DAOSettings memory) {
        return DAOFactory.DAOSettings(address(0), "", nameWithEntropy, "");
    }

    function getPluginSettings(
        PluginRepo pluginRepo
    ) public view returns (DAOFactory.PluginSettings[] memory pluginSettings) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/utils/multisig-addresses.json");
        string memory json = vm.readFile(path);

        address[] memory members = vm.parseJsonAddressArray(json, "$.addresses");

        PolygonMultisig.MultisigSettings memory multisigSettings = PolygonMultisig
            .MultisigSettings({
                onlyListed: onlyListed,
                minApprovals: minApprovals,
                minConfirmations: minConfirmations,
                emergencyMinApprovals: emergencyMinApprovals,
                delayDuration: delayDuration,
                memberOnlyProposalExecution: memberOnlyProposalExecution,
                minExtraDuration: minExtraDuration
            });
        bytes memory pluginSettingsData = abi.encode(
            members,
            multisigSettings,
            secondaryMetadataAdmin
        );

        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        pluginSettings = new DAOFactory.PluginSettings[](1);
        pluginSettings[0] = DAOFactory.PluginSettings(
            PluginSetupRef(tag, pluginRepo),
            pluginSettingsData
        );
    }
}
