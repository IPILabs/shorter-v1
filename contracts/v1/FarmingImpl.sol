// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/AllyLibrary.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/IShorterBone.sol";
import "../interfaces/v1/IFarming.sol";
import "../interfaces/v1/model/IFarmingRewardModel.sol";
import "../interfaces/v1/model/IGovRewardModel.sol";
import "../interfaces/v1/model/IPoolRewardModel.sol";
import "../interfaces/v1/model/ITradingRewardModel.sol";
import "../interfaces/v1/model/IVoteRewardModel.sol";
import "../criteria/ChainSchema.sol";
import "../storage/FarmingStorage.sol";
import "../util/BoringMath.sol";
import "./Rescuable.sol";

contract FarmingImpl is Rescuable, ChainSchema, Pausable, FarmingStorage, IFarming {
    using SafeToken for ISRC20;
    using BoringMath for uint256;

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function stake(uint256 amount) public whenNotPaused onlyEOA {
        require(lpToken != address(0), "Farming: Invalid lpToken");
        shorterBone.tillIn(lpToken, msg.sender, AllyLibrary.FARMING, amount);
        farmingRewardModel.harvest(msg.sender);
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender].add(amount);
        emit Stake(msg.sender, amount);
    }

    function unStake(uint256 amount) public whenNotPaused onlyEOA {
        uint256 userAmount = userStakedAmount[msg.sender];
        require(amount > 0 && userAmount >= amount, "Farming: Invalid withdraw amount");
        farmingRewardModel.harvest(msg.sender);
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender].sub(amount);
        shorterBone.tillOut(lpToken, AllyLibrary.FARMING, msg.sender, amount);
        emit UnStake(msg.sender, amount);
    }

    function getUserStakedAmount(address user) public view override returns (uint256 userStakedAmount_) {
        userStakedAmount_ = userStakedAmount[user];
    }

    function allPendingRewards(address user)
        public
        view
        returns (
            uint256 govRewards,
            uint256 farmingRewards,
            uint256 voteAgainstRewards,
            uint256 tradingRewards,
            uint256 stakedRewards,
            uint256 creatorRewards,
            uint256 voteRewards,
            uint256[] memory tradingRewardPools,
            uint256[] memory stakedRewardPools,
            uint256[] memory createRewardPools,
            uint256[] memory voteRewardPools
        )
    {
        (tradingRewards, tradingRewardPools) = tradingRewardModel.pendingReward(user);
        govRewards = govRewardModel.pendingReward(user);
        voteAgainstRewards = voteRewardModel.pendingReward(user);
        (uint256 unLockRewards_, uint256 rewards_) = farmingRewardModel.pendingReward(user);
        farmingRewards = unLockRewards_.add(rewards_);
        (stakedRewards, creatorRewards, voteRewards, stakedRewardPools, createRewardPools, voteRewardPools) = poolRewardModel.pendingReward(user);
    }

    function harvestAll(
        uint256 govRewards,
        uint256 farmingRewards,
        uint256 voteAgainstRewards,
        uint256[] memory tradingRewardPools,
        uint256[] memory stakedRewardPools,
        uint256[] memory createRewardPools,
        uint256[] memory voteRewardPools
    ) external whenNotPaused onlyEOA {
        uint256 rewards;
        if (tradingRewardPools.length > 0) {
            rewards = rewards.add(tradingRewardModel.harvest(msg.sender, tradingRewardPools));
        }

        if (govRewards > 0) {
            rewards = rewards.add(govRewardModel.harvest(msg.sender));
        }

        if (farmingRewards > 0) {
            farmingRewardModel.harvest(msg.sender);
        }

        if (voteAgainstRewards > 0) {
            rewards = rewards.add(voteRewardModel.harvest(msg.sender));
        }

        if (stakedRewardPools.length > 0 || createRewardPools.length > 0 || voteRewardPools.length > 0) {
            rewards = rewards.add(poolRewardModel.harvest(msg.sender, stakedRewardPools, createRewardPools, voteRewardPools));
        }

        shorterBone.mintByAlly(AllyLibrary.FARMING, msg.sender, rewards);
    }

    function setRewardModel(
        address _tradingRewardModel,
        address _farmingRewardModel,
        address _govRewardModel,
        address _poolRewardModel,
        address _voteRewardModel
    ) public isManager {
        tradingRewardModel = ITradingRewardModel(_tradingRewardModel);
        farmingRewardModel = IFarmingRewardModel(_farmingRewardModel);
        govRewardModel = IGovRewardModel(_govRewardModel);
        poolRewardModel = IPoolRewardModel(_poolRewardModel);
        voteRewardModel = IVoteRewardModel(_voteRewardModel);
    }

    function setLpToken(address _lpToken) public isManager {
        lpToken = _lpToken;
    }

    function initialize(address _shorterBone) external isKeeper {
        require(!_initialized, "Farming: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        _initialized = true;
    }
}
