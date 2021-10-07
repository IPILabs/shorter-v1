// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../libraries/AllyLibrary.sol";
import "../../interfaces/IShorterBone.sol";
import "../../interfaces/governance/ICommittee.sol";
import "../../interfaces/v1/model/IVoteRewardModel.sol";
import "../../criteria/Affinity.sol";
import "../../criteria/ChainSchema.sol";
import "../../storage/model/VoteRewardModelStorage.sol";
import "../../util/BoringMath.sol";
import "../Rescuable.sol";

contract VoteRewardModelImplV1 is Rescuable, ChainSchema, Pausable, VoteRewardModelStorage, IVoteRewardModel {
    using BoringMath for uint256;

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function pendingReward(address user) external view override returns (uint256 _reward) {
        uint256[] memory _againstProposals = getAgainstProposals(user);

        for (uint256 i = 0; i < _againstProposals.length; i++) {
            _reward = _reward.add(_pendingVoteRewardDetail(user, _againstProposals[i]));
        }
    }

    function harvest(address user) external override whenNotPaused returns (uint256 rewards) {
        bool isAccount = user == msg.sender;
        if (!isAccount) {
            require(msg.sender == farming, "VoteReward: Caller is neither Farming nor Farming");
        }

        uint256[] memory _againstProposals = getAgainstProposals(user);
        for (uint256 i = 0; i < _againstProposals.length; i++) {
            rewards = rewards.add(_pendingVoteRewardDetail(user, _againstProposals[i]));
            isUserWithdraw[_againstProposals[i]][user] = true;
        }

        if (isAccount && rewards > 0) {
            shorterBone.mintByAlly(AllyLibrary.VOTE_REWARD, user, rewards);
        }
    }

    function getAgainstProposals(address account) internal view returns (uint256[] memory _againstProposals) {
        (, _againstProposals) = committee.getVoteProposals(account, 1);
    }

    function getAgainstShares(address account, uint256 proposalId) internal view returns (uint256 voteShare, uint256 totalShare) {
        (voteShare, totalShare) = committee.getAgainstShares(account, proposalId);
    }

    function _pendingVoteRewardDetail(address account, uint256 proposalId) internal view returns (uint256 _rewards) {
        (uint256 voteShare, uint256 totalShare) = getAgainstShares(account, proposalId);

        if (voteShare == 0 || totalShare == 0) {
            return 0;
        }

        if (!isUserWithdraw[proposalId][account]) {
            _rewards = ipistrPerProposal.mul(voteShare).div(totalShare);
        }
    }

    function initialize(
        address _shorterBone,
        address _farming,
        address _committee
    ) external isKeeper {
        require(!_initialized, "VoteRewardModel: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        farming = _farming;
        committee = ICommittee(_committee);
        _initialized = true;
    }

    function setIpistrPerProposal(uint256 _amount) external isManager {
        ipistrPerProposal = _amount;
    }
}
