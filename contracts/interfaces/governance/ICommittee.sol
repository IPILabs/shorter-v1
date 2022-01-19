// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

interface ICommittee {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getQueuedProposals() external view returns (uint256[] memory _queuedProposals, uint256[] memory _failedProposals);

    function isRuler(address account) external view returns (bool);

    function getUserShares(address account) external view returns (uint256 totalShare, uint256 lockedShare);

    function executedProposals(uint256[] memory proposalIds, uint256[] memory failedProposals) external;

    function getVoteProposals(address account, uint256 catagory) external view returns (uint256[] memory _forProposals, uint256[] memory _againstProposals);

    function getForShares(address account, uint256 proposalId) external view returns (uint256 voteShare, uint256 totalShare);

    function getAgainstShares(address account, uint256 proposalId) external view returns (uint256 voteShare, uint256 totalShare);

    /// @notice Emitted when a new proposal was created
    event PoolProposalCreated(uint256 indexed proposalId, address indexed proposer);
    /// @notice Emitted when a community proposal was created
    event CommunityProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, string title);
    /// @notice Emitted when one Ruler vote a specified proposal
    event ProposalVoted(uint256 indexed proposalId, address indexed user, bool direction, uint256 voteShare);
    /// @notice Emitted when a proposal was canceled
    event ProposalStatusChanged(uint256 indexed proposalId, uint256 ps);
    /// @notice Emitted when admin tweak the voting period
    event VotingMaxDaysSet(uint256 maxVotingDays);
    /// @notice Emitted when admin tweak ruler threshold parameter
    event RulerThresholdSet(uint256 oldRulerThreshold, uint256 newRulerThreshold);
    /// @notice Emitted when user deposit IPISTRs to Committee vault
    event DepositCommittee(address indexed user, uint256 depositAmount, uint256 totalAmount);
    /// @notice Emitted when user withdraw IPISTRs from Committee vault
    event WithdrawCommittee(address indexed user, uint256 withdrawAmount, uint256 totalAmount);
}
