// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interfaces/governance/IIpistrToken.sol";
import "./TitanCoreStorage.sol";

contract CommitteStorage is TitanCoreStorage {
    // Proposal status enum
    enum ProposalStatus {
        Active,
        Passed,
        Failed,
        Queued,
        Executed
    }

    struct RulerData {
        uint256 stakedAmount;
        uint256 voteShareLocked;
    }

    struct Proposal {
        uint32 id; // Unique id for looking up a proposal
        address proposer; // Creator of the proposal
        uint32 catagory; // 1 = pool 2 = community
        uint64 startBlock; // The block voting starts from
        uint64 endBlock; // The block voting ends at
        uint256 forShares; // Current number of votes in favor of this proposal
        uint256 againstShares; // Current number of votes in opposition to this proposal
        ProposalStatus status;
        bool displayable;
    }

    struct CommunityProposal {
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
    }

    struct PoolMeters {
        address tokenContract; // Address of token contract
        uint32 leverage;
        uint32 durationDays;
    }

    struct VoteSlot {
        address account;
        uint32 direction;
        uint256 share;
    }

    struct voteShares {
        uint256 forShares;
        uint256 againstShares;
    }

    /// @notice Count of whole proposals
    uint256 public proposalCount;

    uint256[] public proposalIds;

    /// @notice Active days for voting
    uint256 public maxVotingDays;
    /// @notice Number of deposit required in order for a user to become a ruler, 1e9/1e12
    uint256 public rulerThreshold;
    /// @notice All staked IPISTR amount
    uint256 public totalIpistrStakedShare;
    /// @notice Contract address of the IPISTR token
    IIpistrToken public ipistrToken;
    /// @notice Charge from ruler who submit a proposal, counted at IPISTR
    uint256 public proposalFee;

    address public stableToken;

    EnumerableSet.UintSet internal queuedProposals;

    // Vote weight = (staked share of user / all staked share) %
    mapping(address => RulerData) internal _rulerDataMap;

    mapping(address => uint256) public ipistrStakedAmount;

    mapping(uint256 => Proposal) public proposalGallery;

    mapping(uint256 => CommunityProposal) internal communityProposalGallery;

    /// @notice (ProposalId = > PoolMeters)
    mapping(uint256 => PoolMeters) public poolMetersMap;

    // proposalId => ruler address => share
    mapping(uint256 => mapping(address => voteShares)) public userLockedShare;

    mapping(uint256 => EnumerableSet.AddressSet) internal proposalVoters;

    mapping(address => EnumerableSet.UintSet) internal forVoteProposals;

    mapping(address => EnumerableSet.UintSet) internal againstVoteProposals;
}
