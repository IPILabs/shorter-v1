// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../../libraries/AllyLibrary.sol";
import "../../interfaces/IShorterBone.sol";
import "../../interfaces/governance/ICommittee.sol";
import "../../interfaces/v1/model/IGovRewardModel.sol";
import "../../criteria/ChainSchema.sol";
import "../../storage/model/GovRewardModelStorage.sol";
import "../../util/BoringMath.sol";

contract GovRewardModelImpl is ChainSchema, GovRewardModelStorage, IGovRewardModel {
    using BoringMath for uint256;
    using AllyLibrary for IShorterBone;

    modifier onlyCommittee() {
        shorterBone.assertCaller(msg.sender, AllyLibrary.COMMITTEE);
        _;
    }

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    function harvest(address user) external override returns (uint256 rewards) {
        bool isAccount = user == msg.sender;
        if (!isAccount) {
            require(msg.sender == farming || msg.sender == committee, "GovReward: Caller is neither Farming nor Committee");
        }

        rewards = pendingReward(user);
        if ((isAccount || msg.sender == committee) && rewards > 0) {
            shorterBone.mintByAlly(AllyLibrary.GOV_REWARD, user, rewards);
        }

        userLastRewardBlock[user] = block.number;
    }

    function pendingReward(address user) public view override returns (uint256 rewards) {
        uint256 _stakedAmount = getUserStakedAmount(user);
        if (_stakedAmount == 0 || userLastRewardBlock[user] == 0) {
            return uint256(0);
        }
        uint256 blockSpan = block.number.sub(userLastRewardBlock[user]);
        rewards = _stakedAmount.mul(blockSpan).mul(ApyPoint).div(getBlockePerYear()).div(100);
    }

    function getUserStakedAmount(address user) public view returns (uint256 _stakedAmount) {
        (_stakedAmount, ) = ICommittee(committee).getUserShares(user);
    }

    function initialize(
        address _shorterBone,
        address _ipistrToken,
        address _farming,
        address _committee
    ) external isSavior {
        require(!_initialized, "GovReward: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        ipistrToken = _ipistrToken;
        farming = _farming;
        committee = _committee;
        ApyPoint = 4;
        _initialized = true;
    }

    function setApyPoint(uint256 newApyPoint) external onlyCommittee {
        ApyPoint = newApyPoint;
    }

    function getBlockePerYear() internal view returns (uint256 _blockSpan) {
        _blockSpan = uint256(31536000).div(secondsPerBlock());
    }
}
