// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {IMultisig} from "./IMultisig.sol";

import {PluginUUPSUpgradeable, IDAO} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {ProposalUpgradeable} from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";

/// @title PolygonMultisig - Release 1, Build 1
/// @author AragonX - 2024
/// @notice The on-chain Polygon Multisig governance plugin in which a proposal passes if X out of Y approvals are met for emergency proposals.
/// or requiring a second round of approvals for non-emergency proposals. The plugin allows for a delay to be started for non-emergency proposals.
contract PolygonMultisig is
    IMultisig,
    IMembership,
    PluginUUPSUpgradeable,
    ProposalUpgradeable,
    Addresslist
{
    using SafeCastUpgradeable for uint256;

    /// @notice MIN_APPROVALS_THRESHOLDS is the minimal number of approvals required for a proposal to pass.
    uint256 immutable MIN_APPROVALS_THRESHOLD = 1;
    uint256 immutable MIN_CONFIRMATIONS_THRESHOLD = 1;

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param approvals The number of approvals casted.
    /// @param parameters The proposal-specific approve settings at the time of the proposal creation.
    /// @param approvers The approves casted by the approvers.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @param confirmations The number of confirmations casted (second approval round).
    /// @param confirmation_approvers The confirmations casted by the confirmers.
    /// @param metadata The metadata of the proposal, usually stored in IPFS.
    /// @param secondaryMetadata The secondary metadata of the proposal, can only be changed once.
    /// @param firstDelayStartTimestamp The block timestamp when the first delay started.
    struct Proposal {
        bool executed;
        uint16 approvals;
        ProposalParameters parameters;
        mapping(address => bool) approvers;
        IDAO.Action[] actions;
        uint256 allowFailureMap;
        uint16 confirmations;
        mapping(address => bool) confirmation_approvers;
        bytes metadata;
        bytes secondaryMetadata;
        uint64 firstDelayStartTimestamp;
    }

    /// @notice A container for the proposal parameters.
    /// @param minApprovals The number of approvals required.
    /// @param minConfirmations The number of approvals required.
    /// @param snapshotBlock The number of the block prior to the proposal creation.
    /// @param startDate The timestamp when the proposal starts.
    /// @param endDate The timestamp when the proposal expires.
    /// @param delayDuration The duration of the delay.
    /// @param emergency Whether the proposal is an emergency proposal or not.
    /// @param emergencyMinApprovals The number of approvals required for an emergency proposal.
    /// @param memberOnlyProposalExecution Boolean to set if only multisig members should be allowed to execute
    /// @param minExtraDuration The minimal extra duration for a proposal endTime for people to vote.
    struct ProposalParameters {
        uint16 minApprovals;
        uint16 minConfirmations;
        uint64 snapshotBlock;
        uint64 startDate;
        uint64 endDate;
        uint64 delayDuration;
        bool emergency;
        uint16 emergencyMinApprovals;
        bool memberOnlyProposalExecution;
        uint256 minExtraDuration;
    }

    /// @notice A container for the plugin settings.
    /// @param onlyListed Whether only listed addresses can create a proposal or not.
    /// @param minApprovals The minimal number of approvals required for a proposal to pass.
    /// @param minConfirmations The minimal number of confirmations required for a proposal to pass.
    /// @param emergencyMinApprovals The minimal number of approvals required for an emergency proposal to pass.
    /// @param delayDuration The duration of the delay.
    /// @param memberOnlyProposalExecution Boolean to set if only multisig members should be allowed to execute
    /// @param minExtraDuration The minimal extra duration for a proposal endTime for people to vote.
    struct MultisigSettings {
        bool onlyListed;
        uint16 minApprovals;
        uint16 minConfirmations;
        uint16 emergencyMinApprovals;
        uint64 delayDuration;
        bool memberOnlyProposalExecution;
        uint256 minExtraDuration;
    }

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant MULTISIG_INTERFACE_ID =
        this.initialize.selector ^
            this.updateMultisigSettings.selector ^
            this.createProposal.selector ^
            this.getProposal.selector;

    /// @notice The ID of the permission required to call the `addAddresses` and `removeAddresses` functions.
    bytes32 public constant UPDATE_MULTISIG_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_MULTISIG_SETTINGS_PERMISSION");

    /// @notice The ID of the permission required to call the `setSecondaryMetadata` function.
    bytes32 public constant SET_SECONDARY_METADATA_PERMISSION_ID =
        keccak256("SET_SECONDARY_METADATA_PERMISSION");

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 => Proposal) internal proposals;

    /// @notice A mapping between the proposal index and the proposal ID.
    mapping(uint256 => uint256) internal proposalIndexToId;

    /// @notice The current plugin settings.
    MultisigSettings public multisigSettings;

    /// @notice Keeps track at which block number the multisig settings have been changed the last time.
    /// @dev This variable prevents a proposal from being created in the same block in which the multisig settings change.
    uint64 public lastMultisigSettingsChange;

    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param sender The sender address.
    error ProposalCreationForbidden(address sender);

    /// @notice Thrown when the secondary metadata can't be set.
    error MetadataCantBeSet();

    /// @notice Thrown when the secondary metadata can't be set.
    error DelayCantBeSet();

    /// @notice Thrown if an approver is not allowed to cast an approve. This can be because the proposal
    /// - is not open,
    /// - was executed, or
    /// - the approver is not on the address list
    /// @param proposalId The ID of the proposal.
    /// @param sender The address of the sender.
    error ApprovalCastForbidden(uint256 proposalId, address sender);

    /// @notice Thrown if a member is not allowed to cast a confirmation.
    /// @param proposalId The ID of the proposal.
    /// @param sender The address of the sender.
    error ConfirmationCastForbidden(uint256 proposalId, address sender);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the minimal approvals value is out of bounds (less than 1 or greater than the number of members in the address list).
    /// @param limit The maximal value.
    /// @param actual The actual value.
    error MinApprovalsOutOfBounds(uint16 limit, uint16 actual);

    /// @notice Thrown if the address list length is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error AddresslistLengthOutOfBounds(uint16 limit, uint256 actual);

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Emitted when sender in not in the member list.
    /// @param account The address of the sender that is not in the member list.
    error NotInMemberList(address account);

    /// @notice Secondary metadata was already set before and can only be set once
    error SecondaryMetadataAlreadySet();

    /// @notice Thrown if the proposal has not enough approvals to start the delay.
    error InsuficientApprovals(uint16 approvals, uint16 minApprovals);

    /// @notice Emitted when the proposal delay has started.
    event ProposalDelayStarted(uint256 proposalId);

    /// @notice Emitted when a proposal is approved by an approver.
    /// @param proposalId The ID of the proposal.
    /// @param approver The approver casting the approve.
    event Approved(uint256 indexed proposalId, address indexed approver);

    /// @notice Emitted when a proposal is confirmed by an approver.
    /// @param proposalId The ID of the proposal.
    /// @param approver The approver casting the approve.
    event Confirmed(uint256 indexed proposalId, address indexed approver);

    /// @notice Emitted when the plugin settings are set.
    /// @param onlyListed Whether only listed addresses can create a proposal.
    /// @param minApprovals The minimum amount of approvals needed to pass a proposal.
    /// @param minConfirmations The minimum amount of approvals needed to pass a proposal.
    /// @param emergencyMinApprovals The minimum amount of approvals needed to pass an emergency proposal.
    /// @param delayDuration The duration of the delay.
    /// @param memberOnlyProposalExecution Boolean to set if only multisig members should be allowed to execute
    /// @param minExtraDuration The minimal extra duration for a proposal endTime for people to vote.
    event MultisigSettingsUpdated(
        bool onlyListed,
        uint16 indexed minApprovals,
        uint16 indexed minConfirmations,
        uint16 emergencyMinApprovals,
        uint64 delayDuration,
        bool memberOnlyProposalExecution,
        uint256 minExtraDuration
    );

    /// @notice Initializes Release 1, Build 1.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _members The addresses of the initial members to be added.
    /// @param _multisigSettings The multisig settings.
    function initialize(
        IDAO _dao,
        address[] calldata _members,
        MultisigSettings calldata _multisigSettings
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        if (_members.length > type(uint16).max) {
            revert AddresslistLengthOutOfBounds({limit: type(uint16).max, actual: _members.length});
        }

        _addAddresses(_members);
        emit MembersAdded({members: _members});

        _updateMultisigSettings(_multisigSettings);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(PluginUUPSUpgradeable, ProposalUpgradeable) returns (bool) {
        return
            _interfaceId == MULTISIG_INTERFACE_ID ||
            _interfaceId == type(IMultisig).interfaceId ||
            _interfaceId == type(Addresslist).interfaceId ||
            _interfaceId == type(IMembership).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IMultisig
    function addAddresses(
        address[] calldata _members
    ) external auth(UPDATE_MULTISIG_SETTINGS_PERMISSION_ID) {
        uint256 newAddresslistLength = addresslistLength() + _members.length;

        // Check if the new address list length would be greater than `type(uint16).max`, the maximal number of approvals.
        if (newAddresslistLength > type(uint16).max) {
            revert AddresslistLengthOutOfBounds({
                limit: type(uint16).max,
                actual: newAddresslistLength
            });
        }

        _addAddresses(_members);

        emit MembersAdded({members: _members});
    }

    /// @inheritdoc IMultisig
    function removeAddresses(
        address[] calldata _members
    ) external auth(UPDATE_MULTISIG_SETTINGS_PERMISSION_ID) {
        uint16 newAddresslistLength = uint16(addresslistLength() - _members.length);

        // Check if the new address list length would become less than the current minimum number of emergency approvals required.
        // Emeregency approvals are always higher or equal to the minimum approvals, so we only need to check the emergency approvals.
        if (newAddresslistLength < multisigSettings.emergencyMinApprovals) {
            revert MinApprovalsOutOfBounds({
                limit: newAddresslistLength,
                actual: multisigSettings.emergencyMinApprovals
            });
        }

        _removeAddresses(_members);

        emit MembersRemoved({members: _members});
    }

    /// @notice Updates the plugin settings.
    /// @param _multisigSettings The new settings.
    function updateMultisigSettings(
        MultisigSettings calldata _multisigSettings
    ) external auth(UPDATE_MULTISIG_SETTINGS_PERMISSION_ID) {
        _updateMultisigSettings(_multisigSettings);
    }

    /// @notice Creates a new multisig proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @param _approveProposal If `true`, the sender will approve the proposal.
    /// @param _startDate The start date of the proposal.
    /// @param _endDate The end date of the proposal.
    /// @param _emergency Whether the proposal is an emergency proposal or not.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        bool _approveProposal,
        uint64 _startDate,
        uint64 _endDate,
        bool _emergency
    ) external returns (uint256 proposalId) {
        if (multisigSettings.onlyListed && !isListed(_msgSender())) {
            revert ProposalCreationForbidden(_msgSender());
        }

        uint64 snapshotBlock;
        unchecked {
            snapshotBlock = block.number.toUint64() - 1; // The snapshot block must be mined already to protect the transaction against backrunning transactions causing census changes.
        }

        // Revert if the settings have been changed in the same block as this proposal should be created in.
        // This prevents a malicious party from voting with previous addresses and the new settings.
        if (lastMultisigSettingsChange > snapshotBlock) {
            revert ProposalCreationForbidden(_msgSender());
        }

        if (_startDate == 0) {
            _startDate = block.timestamp.toUint64();
        } else if (_startDate < block.timestamp.toUint64()) {
            revert DateOutOfBounds({limit: block.timestamp.toUint64(), actual: _startDate});
        }

        if (
            _endDate < _startDate ||
            _startDate + multisigSettings.delayDuration + multisigSettings.minExtraDuration >
            _endDate
        ) {
            revert DateOutOfBounds({limit: _startDate, actual: _endDate});
        }

        proposalId = uint256(
            keccak256(
                abi.encode(
                    _msgSender(),
                    _metadata,
                    _actions,
                    block.number // Include block number for uniqueness
                )
            )
        );

        {
            Proposal storage proposal_ = proposals[proposalId];
            // Checking the proposalId is not already in use
            if (proposal_.parameters.snapshotBlock != 0) {
                revert ProposalCreationForbidden(_msgSender());
            }
            // Index the proposal id by its count
            proposalIndexToId[_createProposalId()] = proposalId;

            // Create the proposal
            proposal_.metadata = _metadata;

            proposal_.parameters.snapshotBlock = snapshotBlock;
            proposal_.parameters.startDate = _startDate;
            proposal_.parameters.endDate = _endDate;
            proposal_.parameters.minApprovals = multisigSettings.minApprovals;
            proposal_.parameters.minConfirmations = multisigSettings.minConfirmations;
            proposal_.parameters.emergency = _emergency;
            proposal_.parameters.emergencyMinApprovals = multisigSettings.emergencyMinApprovals;
            proposal_.parameters.delayDuration = multisigSettings.delayDuration;
            proposal_.parameters.memberOnlyProposalExecution = multisigSettings
                .memberOnlyProposalExecution;
            proposal_.parameters.minExtraDuration = multisigSettings.minExtraDuration;

            // Reduce costs
            if (_allowFailureMap != 0) {
                proposal_.allowFailureMap = _allowFailureMap;
            }

            for (uint256 i; i < _actions.length; ) {
                proposal_.actions.push(_actions[i]);
                unchecked {
                    ++i;
                }
            }
        }

        if (_approveProposal) {
            approve(proposalId);
        }

        emit ProposalCreated({
            proposalId: proposalId,
            creator: _msgSender(),
            metadata: _metadata,
            startDate: _startDate,
            endDate: _endDate,
            actions: _actions,
            allowFailureMap: _allowFailureMap
        });
    }

    /// @inheritdoc IMultisig
    function approve(uint256 _proposalId) public {
        address approver = _msgSender();
        if (!_canApprove(_proposalId, approver)) {
            revert ApprovalCastForbidden(_proposalId, approver);
        }

        Proposal storage proposal_ = proposals[_proposalId];

        // As the list can never become more than type(uint16).max(due to addAddresses check)
        // It's safe to use unchecked as it would never overflow.
        unchecked {
            proposal_.approvals += 1;
        }

        proposal_.approvers[approver] = true;

        emit Approved({proposalId: _proposalId, approver: approver});
    }

    /// @inheritdoc IMultisig
    function confirm(uint256 _proposalId) public {
        address approver = _msgSender();
        if (!_canConfirm(_proposalId, approver)) {
            revert ConfirmationCastForbidden(_proposalId, approver);
        }

        Proposal storage proposal_ = proposals[_proposalId];

        // As the list can never become more than type(uint16).max(due to addAddresses check)
        // It's safe to use unchecked as it would never overflow.
        unchecked {
            proposal_.confirmations += 1;
        }

        proposal_.confirmation_approvers[approver] = true;

        emit Confirmed({proposalId: _proposalId, approver: approver});
    }

    /// @inheritdoc IMultisig
    function canApprove(uint256 _proposalId, address _account) external view returns (bool) {
        return _canApprove(_proposalId, _account);
    }

    /// @inheritdoc IMultisig
    function canConfirm(uint256 _proposalId, address _account) external view returns (bool) {
        return _canConfirm(_proposalId, _account);
    }

    /// @inheritdoc IMultisig
    function canExecute(uint256 _proposalId) external view returns (bool) {
        return _canExecute(_proposalId);
    }

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return executed Whether the proposal is executed or not.
    /// @return approvals The number of approvals casted.
    /// @return parameters The parameters of the proposal vote.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @return confirmations The number of confirmations casted (second approval round).
    /// @return metadata The metadata of the proposal, usually stored in IPFS.
    /// @return secondaryMetadata The secondary metadata of the proposal, can only be changed once.
    /// @return firstDelayStartTimestamp The block timestamp when the first delay started.
    function getProposal(
        uint256 _proposalId
    )
        public
        view
        returns (
            bool executed,
            uint16 approvals,
            ProposalParameters memory parameters,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap,
            uint16 confirmations,
            bytes memory metadata,
            bytes memory secondaryMetadata,
            uint64 firstDelayStartTimestamp
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        executed = proposal_.executed;
        approvals = proposal_.approvals;
        parameters = proposal_.parameters;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
        confirmations = proposal_.confirmations;
        metadata = proposal_.metadata;
        secondaryMetadata = proposal_.secondaryMetadata;
        firstDelayStartTimestamp = proposal_.firstDelayStartTimestamp;
    }

    /// @notice Returns the proposal id given its index.
    /// @param _proposalIndex The index of the proposal.
    /// @return The ID of the proposal.
    function getProposalIdByIndex(uint256 _proposalIndex) external view returns (uint256) {
        return proposalIndexToId[_proposalIndex];
    }

    /// @notice Returns all information for a proposal vote by its index.
    /// @param _proposalIndex The index of the proposal.
    /// @return executed Whether the proposal is executed or not.
    /// @return approvals The number of approvals casted.
    /// @return parameters The parameters of the proposal vote.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @return confirmations The number of confirmations casted (second approval round).
    /// @return metadata The metadata of the proposal, usually stored in IPFS.
    /// @return secondaryMetadata The secondary metadata of the proposal, can only be changed once.
    /// @return firstDelayStartTimestamp The block timestamp when the first delay started.
    function getProposalByIndex(
        uint256 _proposalIndex
    )
        external
        view
        returns (
            bool executed,
            uint16 approvals,
            ProposalParameters memory parameters,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap,
            uint16 confirmations,
            bytes memory metadata,
            bytes memory secondaryMetadata,
            uint64 firstDelayStartTimestamp
        )
    {
        return getProposal(proposalIndexToId[_proposalIndex]);
    }

    /// @inheritdoc IMultisig
    function hasApproved(uint256 _proposalId, address _account) public view returns (bool) {
        return proposals[_proposalId].approvers[_account];
    }

    /// @notice Allows to start the delay for a proposal. Can only be done for normal proposals right after approvals are reached.
    /// @param _proposalId The ID of the proposal.
    function startProposalDelay(uint256 _proposalId) external {
        Proposal storage proposal_ = proposals[_proposalId];

        uint64 currentTimestamp64 = block.timestamp.toUint64();

        if (
            uint64(proposal_.parameters.endDate) < currentTimestamp64 ||
            proposal_.parameters.emergency ||
            proposal_.firstDelayStartTimestamp != 0
        ) {
            revert DelayCantBeSet();
        }

        if (!isListedAtBlock(_msgSender(), proposal_.parameters.snapshotBlock)) {
            revert NotInMemberList(_msgSender());
        }

        if (proposal_.approvals < proposal_.parameters.minApprovals) {
            revert InsuficientApprovals(proposal_.approvals, proposal_.parameters.minApprovals);
        }

        proposal_.firstDelayStartTimestamp = block.timestamp.toUint64();
        emit ProposalDelayStarted(_proposalId);
    }

    /// @inheritdoc IMultisig
    function execute(uint256 _proposalId) public {
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        _execute(_proposalId);
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        return isListed(_account);
    }

    /// @notice Internal function to execute a vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    function _execute(uint256 _proposalId) internal {
        Proposal storage proposal_ = proposals[_proposalId];

        proposal_.executed = true;

        _executeProposal(
            dao(),
            _proposalId,
            proposals[_proposalId].actions,
            proposals[_proposalId].allowFailureMap
        );
    }

    /// @notice Internal function to check if an account can approve. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account to check.
    /// @return Returns `true` if the given account can approve on a certain proposal and `false` otherwise.
    function _canApprove(uint256 _proposalId, address _account) internal view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        if (!_isProposalOpen(proposal_)) {
            // The proposal was executed already
            return false;
        }

        if (proposal_.firstDelayStartTimestamp != 0) {
            // The delay has already started
            return false;
        }

        if (!isListedAtBlock(_account, proposal_.parameters.snapshotBlock)) {
            // The approver has no voting power.
            return false;
        }

        if (proposal_.approvers[_account]) {
            // The approver has already approved
            return false;
        }

        return true;
    }

    /// @notice Internal function to check if an account can confirm a proposal. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account to check.
    /// @return Returns `true` if the given account can confirm on a certain proposal and `false` otherwise.
    function _canConfirm(uint256 _proposalId, address _account) internal view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        if (!_isProposalOpen(proposal_)) {
            // The proposal was executed already
            return false;
        }

        if (!isListedAtBlock(_account, proposal_.parameters.snapshotBlock)) {
            // The confirmer has no voting power.
            return false;
        }

        if (
            proposal_.firstDelayStartTimestamp == 0 ||
            proposal_.firstDelayStartTimestamp + proposal_.parameters.delayDuration >
            block.timestamp
        ) {
            // The delay has not started yet or hasn't ended
            return false;
        }

        if (proposal_.confirmation_approvers[_account]) {
            // The confirmer has already confirmed
            return false;
        }

        return true;
    }

    /// @notice Internal function to check if a proposal can be executed. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the proposal can be executed and `false` otherwise.
    function _canExecute(uint256 _proposalId) internal view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the proposal has not been executed or expired.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        if (
            proposal_.parameters.memberOnlyProposalExecution &&
            !isListedAtBlock(_msgSender(), proposal_.parameters.snapshotBlock)
        ) {
            return false;
        }

        return
            proposal_.parameters.emergency
                ? proposal_.approvals >= proposal_.parameters.emergencyMinApprovals
                : (proposal_.approvals >= proposal_.parameters.minApprovals &&
                    proposal_.confirmations >= proposal_.parameters.minConfirmations);
    }

    /// @notice Internal function to check if a proposal vote is still open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal vote is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view returns (bool) {
        uint64 currentTimestamp64 = block.timestamp.toUint64();
        return
            !proposal_.executed &&
            proposal_.parameters.startDate <= currentTimestamp64 &&
            proposal_.parameters.endDate >= currentTimestamp64;
    }

    /// @notice Internal function to update the plugin settings.
    /// @param _multisigSettings The new settings.
    function _updateMultisigSettings(MultisigSettings calldata _multisigSettings) internal {
        uint16 addresslistLength_ = uint16(addresslistLength());

        if (_multisigSettings.minApprovals > _multisigSettings.emergencyMinApprovals) {
            revert MinApprovalsOutOfBounds({
                limit: _multisigSettings.emergencyMinApprovals,
                actual: _multisigSettings.minApprovals
            });
        }

        if (
            _multisigSettings.minApprovals > addresslistLength_ ||
            _multisigSettings.emergencyMinApprovals > addresslistLength_
        ) {
            revert MinApprovalsOutOfBounds({
                limit: addresslistLength_,
                actual: _multisigSettings.minApprovals
            });
        }

        if (
            _multisigSettings.minApprovals < MIN_APPROVALS_THRESHOLD ||
            _multisigSettings.emergencyMinApprovals < MIN_APPROVALS_THRESHOLD ||
            _multisigSettings.minConfirmations < MIN_CONFIRMATIONS_THRESHOLD
        ) {
            revert MinApprovalsOutOfBounds({limit: 1, actual: _multisigSettings.minApprovals});
        }

        multisigSettings = _multisigSettings;
        lastMultisigSettingsChange = block.number.toUint64();

        emit MultisigSettingsUpdated({
            onlyListed: _multisigSettings.onlyListed,
            minApprovals: _multisigSettings.minApprovals,
            minConfirmations: _multisigSettings.minConfirmations,
            emergencyMinApprovals: _multisigSettings.emergencyMinApprovals,
            delayDuration: _multisigSettings.delayDuration,
            memberOnlyProposalExecution: _multisigSettings.memberOnlyProposalExecution,
            minExtraDuration: _multisigSettings.minExtraDuration
        });
    }

    /// @notice Allows to set the secondary metadata of a proposal.
    /// @param _proposalId The id of the proposal to be changed.
    /// @param _secondaryMetadata The secondary metadata of the proposal.
    function setSecondaryMetadata(
        uint256 _proposalId,
        bytes calldata _secondaryMetadata
    ) public auth(SET_SECONDARY_METADATA_PERMISSION_ID) {
        Proposal storage proposal_ = proposals[_proposalId];
        uint64 currentTimestamp64 = block.timestamp.toUint64();

        if (proposal_.executed || uint64(proposal_.parameters.endDate) < currentTimestamp64) {
            revert MetadataCantBeSet();
        }

        proposal_.secondaryMetadata = _secondaryMetadata;
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;
}
