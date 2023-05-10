// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../../libraries/AllyLibrary.sol";
import "../../interfaces/v1/model/IPoolRewardModel.sol";
import "../../interfaces/IPool.sol";
import "../../criteria/ChainSchema.sol";
import "../../storage/model/PoolRewardModelStorage.sol";
import "../../util/BoringMath.sol";

contract PoolRewardModelImpl is ChainSchema, PoolRewardModelStorage, IPoolRewardModel {
    using BoringMath for uint256;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    function harvest(address user, uint256[] memory stakedPools, uint256[] memory createPools, uint256[] memory votePools) external override whenNotPaused returns (uint256 rewards) {
            require(msg.sender == farming, "PoolReward: Caller is not Farming");
        for (uint256 i = 0; i < stakedPools.length; i++) {
            rewards = rewards.add(pendingPoolReward(user, stakedPools[i]));
            _updatePool(stakedPools[i]);

            address strPool = getStrPool(stakedPools[i]);
            _updatePoolRewardDetail(user, stakedPools[i], ISRC20(strPool).balanceOf(user));
        }

        for (uint256 i = 0; i < createPools.length; i++) {
            (uint256 _creatorRewards, uint256 _creatorRewards0, uint256 _creatorRewards1) = pendingCreatorRewards(user, createPools[i]);
            rewards = rewards.add(_creatorRewards);

            _updatePool(createPools[i]);
            _updateCreateRewardDetail(user, createPools[i], _creatorRewards0, _creatorRewards1);
        }

        for (uint256 i = 0; i < votePools.length; i++) {
            (uint256 _voteRewards, uint256 _voteRewards0, uint256 _voteRewards1) = pendingVoteRewards(user, votePools[i]);
            rewards = rewards.add(_voteRewards);

            _updatePool(votePools[i]);
            _updateVoteRewardDetail(user, votePools[i], _voteRewards0, _voteRewards1);
        }
    }

    function harvestByStrToken(uint256 poolId, address user, uint256 amount) external override {
        address strPool = getStrPool(poolId);
        require(msg.sender == strPool, "PoolReward: Caller is not the Pool");
        uint256 _rewards = pendingPoolReward(user, poolId);

        _updatePool(poolId);
        _updatePoolRewardDetail(user, poolId, amount);

        if (_rewards > 0) {
            shorterBone.mintByAlly(AllyLibrary.POOL_REWARD, user, _rewards);
        }
    }

    function pendingReward(address user) public view override returns (uint256 stakedRewards, uint256 creatorRewards, uint256 voteRewards, uint256[] memory stakedPools, uint256[] memory createPools, uint256[] memory votePools) {
        uint256[] memory poodIds = _getPools();
        (stakedRewards, stakedPools) = _pendingPoolReward(user, poodIds);
        (creatorRewards, createPools) = _pendingCreateReward(user, poodIds);
        (voteRewards, votePools) = _pendingVoteReward(user, poodIds);
    }

    function _pendingCreateReward(address user, uint256[] memory poodIds) internal view returns (uint256 creatorRewards, uint256[] memory createPools) {
        uint256 poolSize = poodIds.length;

        uint256[] memory createPoolContainer = new uint256[](poolSize);

        uint256 resCreatePoolCount;
        for (uint256 i = 0; i < poodIds.length; i++) {
            (uint256 _creatorRewards, , ) = pendingCreatorRewards(user, poodIds[i]);
            if (_creatorRewards > 0) {
                creatorRewards = creatorRewards.add(_creatorRewards);
                createPoolContainer[resCreatePoolCount++] = poodIds[i];
            }
        }

        createPools = new uint256[](resCreatePoolCount);
        for (uint256 i = 0; i < resCreatePoolCount; i++) {
            createPools[i] = createPoolContainer[i];
        }
    }

    function _pendingPoolReward(address user, uint256[] memory poodIds) internal view returns (uint256 stakedRewards, uint256[] memory stakedPools) {
        uint256 poolSize = poodIds.length;
        uint256[] memory stakedPoolContainer = new uint256[](poolSize);
        uint256 resStakedPoolCount;
        for (uint256 i = 0; i < poodIds.length; i++) {
            uint256 _stakedRewards = pendingPoolReward(user, poodIds[i]);

            if (_stakedRewards > 0) {
                stakedRewards = stakedRewards.add(_stakedRewards);
                stakedPoolContainer[resStakedPoolCount++] = poodIds[i];
            }
        }

        stakedPools = new uint256[](resStakedPoolCount);
        for (uint256 i = 0; i < resStakedPoolCount; i++) {
            stakedPools[i] = stakedPoolContainer[i];
        }
    }

    function _pendingVoteReward(address user, uint256[] memory poodIds) internal view returns (uint256 voteRewards, uint256[] memory votePools) {
        uint256 poolSize = poodIds.length;
        uint256[] memory votePoolContainer = new uint256[](poolSize);

        uint256 resVotePoolCount;
        for (uint256 i = 0; i < poodIds.length; i++) {
            (uint256 _voteRewards, , ) = pendingVoteRewards(user, poodIds[i]);
            if (_voteRewards > 0) {
                voteRewards = voteRewards.add(_voteRewards);
                votePoolContainer[resVotePoolCount++] = poodIds[i];
            }
        }

        votePools = new uint256[](resVotePoolCount);
        for (uint256 i = 0; i < resVotePoolCount; i++) {
            votePools[i] = votePoolContainer[i];
        }
    }

    function pendingPoolReward(address user, uint256 poolId) public view returns (uint256 rewards) {
        PoolInfo storage pool = poolInfoMap[poolId];
        address strPool = getStrPool(poolId);

        uint256 _poolStakedAmount = ISRC20(strPool).totalSupply();
        if (_poolStakedAmount == 0) {
            return 0;
        }

        (, , , , , , , uint256 endBlock, , , uint256 stableTokenDecimals, ) = IPool(strPool).getMetaInfo();

        {
            uint256 stablePoolReward = (IPool(strPool).totalTradingFee().sub(totalTradingFees[poolId])).mul(10 ** (uint256(18).sub(stableTokenDecimals)));
        uint256 accIpistrPerShare = pool.accIPISTRPerShare.add(_totalPendingReward(poolId, endBlock, strPool).div(_poolStakedAmount));
        uint256 accStablePerShare = pool.accStablePerShare.add(stablePoolReward.mul(IPISTR_DECIMAL_SCALER).div(_poolStakedAmount));

        uint256 _userStakedAmount = ISRC20(strPool).balanceOf(user);
        RewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];

        uint256 pendingTradingRewards = _userStakedAmount.mul(accStablePerShare).div(IPISTR_DECIMAL_SCALER).sub(rewardDebt.poolStableRewardDebt);
        uint256 currentPrice = priceOracle.getLatestMixinPrice(ipistrToken);
        pendingTradingRewards = pendingTradingRewards.mul(1e18).mul(2).div(currentPrice).div(5);
        rewards = _userStakedAmount.mul(accIpistrPerShare).div(IPISTR_DECIMAL_SCALER).sub(rewardDebt.poolIpistrRewardDebt);
        rewards = rewards.add(pendingTradingRewards);
    }

        rewards = rewards.mul(uint256(1e6).sub(IPool(strPool).poolCreationFee())).div(1e6);
    }

    function pendingCreatorRewards(address user, uint256 poolId) public view returns (uint256 rewards, uint256 rewards0, uint256 rewards1) {
        address strPool = getStrPool(poolId);
        (address creator, , , , , , , uint256 endBlock, , , uint256 stableTokenDecimals, IPoolGuardian.PoolStatus stateFlag) = IPool(strPool).getMetaInfo();
        if (user != creator || stateFlag == IPoolGuardian.PoolStatus.GENESIS) {
            return (0, 0, 0);
        }

        uint256 ipistrPoolReward = (_totalPendingReward(poolId, endBlock, strPool).div(IPISTR_DECIMAL_SCALER)).add(totalIpistrAmount[poolId]);
        uint256 stablePoolReward = IPool(strPool).totalTradingFee().mul(10 ** (uint256(18).sub(stableTokenDecimals)));

        RewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];

        uint256 poolCreationFee = IPool(strPool).poolCreationFee();
        rewards0 = ipistrPoolReward.mul(poolCreationFee).div(1e6) > rewardDebt.creatorIpistrRewardDebt ? (ipistrPoolReward.mul(poolCreationFee).div(1e6)).sub(rewardDebt.creatorIpistrRewardDebt) : 0;
        rewards1 = stablePoolReward.mul(poolCreationFee).div(1e6) > rewardDebt.creatorStableRewardDebt ? (stablePoolReward.mul(poolCreationFee).div(1e6)).sub(rewardDebt.creatorStableRewardDebt) : 0;
        uint256 currentPrice = priceOracle.getLatestMixinPrice(ipistrToken);
        rewards = rewards0.add(rewards1.mul(1e18).div(currentPrice));
    }

    function pendingVoteRewards(address user, uint256 poolId) public view returns (uint256 rewards, uint256 rewards0, uint256 rewards1) {
        (uint256 voteShare, uint256 totalShare) = getForShares(user, poolId);

        if (voteShare == 0) {
            return (0, 0, 0);
        }

        address strPool = getStrPool(poolId);
        (, , , , , , , uint256 endBlock, , , uint256 stableTokenDecimals, ) = IPool(strPool).getMetaInfo();

        uint256 ipistrPoolReward = (_totalPendingReward(poolId, endBlock, strPool).div(IPISTR_DECIMAL_SCALER)).add(totalIpistrAmount[poolId]);
        uint256 stablePoolReward = IPool(strPool).totalTradingFee().mul(10 ** (uint256(18).sub(stableTokenDecimals)));

        RewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewards0 = ipistrPoolReward.mul(voteShare).div(totalShare).div(200) > rewardDebt.voterIpistrRewardDebt ? (ipistrPoolReward.mul(voteShare).div(totalShare).div(200)).sub(rewardDebt.voterIpistrRewardDebt) : 0;
        rewards1 = stablePoolReward.mul(voteShare).div(totalShare).div(200) > rewardDebt.voterStableRewardDebt ? (stablePoolReward.mul(voteShare).div(totalShare).div(200)).sub(rewardDebt.voterStableRewardDebt) : 0;
        uint256 currentPrice = priceOracle.getLatestMixinPrice(ipistrToken);
        rewards = rewards0.add(rewards1.mul(1e18).div(currentPrice));
    }

    function _totalPendingReward(uint256 poolId, uint256 endBlock, address strPool) internal view returns (uint256 _rewards) {
        PoolInfo storage pool = poolInfoMap[poolId];
        uint256 blockSpan = block.number.sub(uint256(pool.lastRewardBlock));
        uint256 poolStakedAmount = ISRC20(strPool).totalSupply();
        if (uint256(pool.lastRewardBlock) >= endBlock || pool.lastRewardBlock == 0 || poolStakedAmount == 0) {
            return 0;
        }

        if (endBlock < block.number) {
            blockSpan = endBlock.sub(uint256(pool.lastRewardBlock));
        }

        if (totalAllocWeight > 0 && blockSpan > 0) {
            _rewards = blockSpan.mul(ipistrPerBlock).mul(pool.allocPoint).mul(pool.multiplier).div(totalAllocWeight).mul(IPISTR_DECIMAL_SCALER);
        }
    }

    function _updatePool(uint256 poolId) internal {
        address strPool = getStrPool(poolId);
        PoolInfo storage pool = poolInfoMap[poolId];

        uint256 poolStakedAmount = ISRC20(strPool).totalSupply();
        if (block.number <= uint256(pool.lastRewardBlock) || poolStakedAmount == 0) {
            pool.lastRewardBlock = block.number.to64();
            return;
        }

        (, , , , , , , uint256 endBlock, , , , ) = IPool(strPool).getMetaInfo();
        uint256 ipistrPoolReward = _totalPendingReward(poolId, endBlock, strPool);
        uint256 stablePoolReward = IPool(strPool).totalTradingFee().sub(totalTradingFees[poolId]);

        totalIpistrAmount[poolId] = totalIpistrAmount[poolId].add(ipistrPoolReward.div(IPISTR_DECIMAL_SCALER));
        totalTradingFees[poolId] = IPool(strPool).totalTradingFee();

        pool.accIPISTRPerShare = pool.accIPISTRPerShare.add(ipistrPoolReward.div(poolStakedAmount));
        pool.accStablePerShare = pool.accStablePerShare.add(stablePoolReward.mul(IPISTR_DECIMAL_SCALER).div(poolStakedAmount));
        pool.lastRewardBlock = block.number.to64();
    }

    function _updateCreateRewardDetail(address user, uint256 poolId, uint256 rewards0, uint256 rewards1) internal {
        RewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewardDebt.creatorIpistrRewardDebt = rewardDebt.creatorIpistrRewardDebt.add(rewards0);
        rewardDebt.creatorStableRewardDebt = rewardDebt.creatorStableRewardDebt.add(rewards1);
    }

    function _updateVoteRewardDetail(address user, uint256 poolId, uint256 rewards0, uint256 rewards1) internal {
        RewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewardDebt.voterIpistrRewardDebt = rewardDebt.voterIpistrRewardDebt.add(rewards0);
        rewardDebt.voterStableRewardDebt = rewardDebt.voterStableRewardDebt.add(rewards1);
    }

    function _updatePoolRewardDetail(address user, uint256 poolId, uint256 amount) internal {
        PoolInfo storage pool = poolInfoMap[poolId];
        RewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewardDebt.poolIpistrRewardDebt = amount.mul(pool.accIPISTRPerShare).div(IPISTR_DECIMAL_SCALER);
        rewardDebt.poolStableRewardDebt = amount.mul(pool.accStablePerShare).div(IPISTR_DECIMAL_SCALER);
    }

    function _getPools() internal view returns (uint256[] memory _poodIds) {
        _poodIds = poolGuardian.getPoolIds();
    }

    function getStrPool(uint256 poolId) public view returns (address strPool) {
        (, strPool, ) = poolGuardian.getPoolInfo(poolId);
    }

    function getForShares(address account, uint256 poolId) internal view returns (uint256 voteShare, uint256 totalShare) {
        (voteShare, totalShare) = committee.getForShares(account, poolId);
    }

    function setAllocPoint(uint256[] calldata _poolIds, uint256[] calldata _allocPoints) external isManager {
        require(_poolIds.length == _allocPoints.length, "PoolReward: Invalid params");
        for (uint256 i = 0; i < _poolIds.length; i++) {
            uint256 _befPoolWeight = _getBefPoolWeight(_poolIds[i]);
            (address stakedToken, , ) = poolGuardian.getPoolInfo(_poolIds[i]);
            (, , uint256 _multiplier) = shorterBone.getTokenInfo(stakedToken);
            if (poolInfoMap[_poolIds[i]].multiplier != _multiplier) {
                poolInfoMap[_poolIds[i]].multiplier = _multiplier.to64();
            }
            uint256 _aftPoolWeight = uint256(poolInfoMap[_poolIds[i]].multiplier).mul(_allocPoints[i]);
            totalAllocWeight = totalAllocWeight.sub(_befPoolWeight).add(_aftPoolWeight);
            poolInfoMap[_poolIds[i]].allocPoint = _allocPoints[i].to64();
            _updatePool(_poolIds[i]);
        }
    }

    function setIpistrPerBlock(uint256 _ipistrPerBlock) external isKeeper {
        uint256[] memory onlinePools = poolGuardian.queryPools(address(0), IPoolGuardian.PoolStatus.RUNNING);
        for (uint256 i = 0; i < onlinePools.length; i++) {
            _updatePool(onlinePools[i]);
        }
        ipistrPerBlock = _ipistrPerBlock;
    }

    function _getBefPoolWeight(uint256 _poolId) internal view returns (uint256 _befPoolWeight) {
        _befPoolWeight = uint256(poolInfoMap[_poolId].allocPoint).mul(poolInfoMap[_poolId].multiplier);
    }

    function setPriceOracle(address newPriceOracle) external isSavior {
        require(newPriceOracle != address(0), "PoolReward: newPriceOracle is zero address");
        priceOracle = IPriceOracle(newPriceOracle);
    }

    function setFarming(address newFarming) external isSavior {
        require(newFarming != address(0), "PoolReward: newFarming is zero address");
        farming = newFarming;
    }

    function initialize(address _shorterBone, address _poolGuardian, address _priceOracle, address _ipistrToken, address _committee, address _farming) external isSavior {
        require(!_initialized, "PoolReward: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
        priceOracle = IPriceOracle(_priceOracle);
        committee = ICommittee(_committee);
        ipistrToken = _ipistrToken;
        farming = _farming;
        _initialized = true;
    }
}
