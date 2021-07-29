// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../../libraries/AllyLibrary.sol";
import "../../interfaces/IShorterBone.sol";
import "../../interfaces/v1/model/IPoolRewardModel.sol";
import "../../interfaces/IStrPool.sol";
import "../../criteria/Affinity.sol";
import "../../criteria/ChainSchema.sol";
import "../../storage/model/PoolRewardModelStorage.sol";
import "../../util/BoringMath.sol";
import "../Rescuable.sol";

contract PoolRewardModelImplV1 is Rescuable, ChainSchema, Pausable, PoolRewardModelStorage, IPoolRewardModel {
    using BoringMath for uint256;

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function harvest(
        address user,
        uint256[] memory stakedPools,
        uint256[] memory createPools,
        uint256[] memory votePools
    ) external override whenNotPaused returns (uint256 rewards) {
        bool isAccount = user == msg.sender;
        if (!isAccount) {
            require(msg.sender == farming, "PoolRewardModel: Caller is not Farming");
        }

        for (uint256 i = 0; i < stakedPools.length; i++) {
            rewards = rewards.add(pendingPoolReward(user, stakedPools[i]));
            updatePool(stakedPools[i]);

            address strPool = getStrPool(stakedPools[i]);
            updatePoolRewardDetail(user, stakedPools[i], ISRC20(strPool).balanceOf(user));
        }

        for (uint256 i = 0; i < createPools.length; i++) {
            (uint256 _creatorRewards, uint256 _creatorRewards0, uint256 _creatorRewards1) = pendingCreatorRewards(user, createPools[i]);
            rewards = rewards.add(_creatorRewards);

            updatePool(createPools[i]);
            updateCreateRewardDetail(user, createPools[i], _creatorRewards0, _creatorRewards1);
        }

        for (uint256 i = 0; i < votePools.length; i++) {
            (uint256 _voteRewards, uint256 _voteRewards0, uint256 _voteRewards1) = pendingVoteRewards(user, votePools[i]);
            rewards = rewards.add(_voteRewards);

            updatePool(votePools[i]);
            updateVoteRewardDetail(user, votePools[i], _voteRewards0, _voteRewards1);
        }

        if (isAccount) {
            shorterBone.mintByAlly(AllyLibrary.POOL_REWARD, user, rewards);
        }
    }

    function harvestByStrToken(
        uint256 poolId,
        address user,
        uint256 amount
    ) external override {
        address strPool = getStrPool(poolId);
        require(msg.sender == strPool, "PoolRewardModel: Caller is not the StrPool");
        uint256 _rewards = pendingPoolReward(user, poolId);

        updatePool(poolId);
        updatePoolRewardDetail(user, poolId, amount);

        if (_rewards > 0) {
            shorterBone.mintByAlly(AllyLibrary.POOL_REWARD, user, _rewards);
        }
    }

    function pendingReward(address user)
        public
        view
        override
        returns (
            uint256 stakedRewards,
            uint256 creatorRewards,
            uint256 voteRewards,
            uint256[] memory stakedPools,
            uint256[] memory createPools,
            uint256[] memory votePools
        )
    {
        uint256[] memory poodIds = getPools();
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
        poolInfo storage pool = poolInfoMap[poolId];
        address strPool = getStrPool(poolId);

        uint256 _poolStakedAmount = ISRC20(strPool).totalSupply();
        if (_poolStakedAmount == 0) {
            return 0;
        }

        (, , , , , , , uint256 endBlock, , , uint256 stableTokenDecimals, ) = IStrPool(strPool).getInfo();

        uint256 stablePoolReward = (IStrPool(strPool).totalTradingFee().sub(totalTradingFees[poolId])).mul(10**(uint256(18).sub(stableTokenDecimals)));
        uint256 accIpistrPerShare = pool.accIPISTRPerShare.add(_totalPendingReward(poolId, endBlock).div(_poolStakedAmount));
        uint256 accStablePerShare = pool.accStablePerShare.add(stablePoolReward.mul(IPISTR_DECIMAL_SCALER).div(_poolStakedAmount));

        uint256 _userStakedAmount = ISRC20(strPool).balanceOf(user);
        rewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];

        uint256 pendingTradingRewards = _userStakedAmount.mul(accStablePerShare).div(IPISTR_DECIMAL_SCALER).sub(rewardDebt.poolStableRewardDebt);
        (uint256 currentPrice, uint256 tokenDecimals) = priceOracle.getLatestMixinPrice(ipistrToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));
        pendingTradingRewards = pendingTradingRewards.mul(1e18).mul(2).div(currentPrice).div(5);

        rewards = _userStakedAmount.mul(accIpistrPerShare).div(IPISTR_DECIMAL_SCALER).sub(rewardDebt.poolIpiStrRewardDebt);
        rewards = rewards.add(pendingTradingRewards);
    }

    function pendingCreatorRewards(address user, uint256 poolId)
        public
        view
        returns (
            uint256 rewards,
            uint256 rewards0,
            uint256 rewards1
        )
    {
        address strPool = getStrPool(poolId);
        (address creator, , , , , , , uint256 endBlock, , , uint256 stableTokenDecimals, ) = IStrPool(strPool).getInfo();
        if (user != creator) {
            return (0, 0, 0);
        }

        uint256 ipistrPoolReward = (_totalPendingReward(poolId, endBlock).div(IPISTR_DECIMAL_SCALER)).add(totalIpiStrAmount[poolId]);
        uint256 stablePoolReward = IStrPool(strPool).totalTradingFee().mul(10**(uint256(18).sub(stableTokenDecimals)));

        rewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewards0 = (ipistrPoolReward.mul(3).div(100)).sub(rewardDebt.creatorIpiStrRewardDebt);
        rewards1 = (stablePoolReward.mul(3).div(100)).sub(rewardDebt.creatorStableRewardDebt);

        (uint256 currentPrice, uint256 tokenDecimals) = priceOracle.getLatestMixinPrice(ipistrToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));
        rewards = rewards0.add(rewards1.mul(1e18).div(currentPrice));
    }

    function pendingVoteRewards(address user, uint256 poolId)
        public
        view
        returns (
            uint256 rewards,
            uint256 rewards0,
            uint256 rewards1
        )
    {
        (uint256 voteShare, uint256 totalShare) = getForShares(user, poolId);

        if (voteShare == 0) {
            return (0, 0, 0);
        }

        address strPool = getStrPool(poolId);
        (, , , , , , , uint256 endBlock, , , uint256 stableTokenDecimals, ) = IStrPool(strPool).getInfo();

        uint256 ipistrPoolReward = (_totalPendingReward(poolId, endBlock).div(IPISTR_DECIMAL_SCALER)).add(totalIpiStrAmount[poolId]);
        uint256 stablePoolReward = IStrPool(strPool).totalTradingFee().mul(10**(uint256(18).sub(stableTokenDecimals)));

        rewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewards0 = (ipistrPoolReward.mul(voteShare).div(totalShare).div(200)).sub(rewardDebt.voterIpiStrRewardDebt);
        rewards1 = (stablePoolReward.mul(voteShare).div(totalShare).div(200)).sub(rewardDebt.voterStableRewardDebt);

        (uint256 currentPrice, uint256 tokenDecimals) = priceOracle.getLatestMixinPrice(ipistrToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));
        rewards = rewards0.add(rewards1.mul(1e18).div(currentPrice));
    }

    function _totalPendingReward(uint256 poolId, uint256 endBlock) internal view returns (uint256 _rewards) {
        poolInfo storage pool = poolInfoMap[poolId];
        uint256 blockSpan = block.number.sub(uint256(pool.lastRewardBlock));
        if (uint256(pool.lastRewardBlock) >= endBlock || pool.lastRewardBlock == 0) {
            return 0;
        }

        if (endBlock < block.number) {
            blockSpan = endBlock.sub(uint256(pool.lastRewardBlock));
        }

        if (totalAllocWeight > 0 && blockSpan > 0) {
            _rewards = blockSpan.mul(ipistrPerBlock).mul(pool.allocPoint).mul(pool.multiplier).div(totalAllocWeight).mul(IPISTR_DECIMAL_SCALER);
        }
    }

    function updatePool(uint256 poolId) internal {
        address strPool = getStrPool(poolId);
        poolInfo storage pool = poolInfoMap[poolId];

        uint256 poolStakedAmount = ISRC20(strPool).totalSupply();
        if (block.number <= uint256(pool.lastRewardBlock) || poolStakedAmount == 0) {
            pool.lastRewardBlock = block.number.to64();
            return;
        }

        (, , , , , , , uint256 endBlock, , , , ) = IStrPool(strPool).getInfo();
        uint256 ipistrPoolReward = _totalPendingReward(poolId, endBlock);
        uint256 stablePoolReward = IStrPool(strPool).totalTradingFee().sub(totalTradingFees[poolId]);

        totalIpiStrAmount[poolId] = totalIpiStrAmount[poolId].add(ipistrPoolReward.div(IPISTR_DECIMAL_SCALER));
        totalTradingFees[poolId] = IStrPool(strPool).totalTradingFee();

        pool.accIPISTRPerShare = pool.accIPISTRPerShare.add(ipistrPoolReward.div(poolStakedAmount));
        pool.accStablePerShare = pool.accStablePerShare.add(stablePoolReward.mul(IPISTR_DECIMAL_SCALER).div(poolStakedAmount));
        pool.lastRewardBlock = block.number.to64();
    }

    function updateCreateRewardDetail(
        address user,
        uint256 poolId,
        uint256 rewards0,
        uint256 rewards1
    ) internal {
        rewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewardDebt.creatorIpiStrRewardDebt = rewardDebt.creatorIpiStrRewardDebt.add(rewards0);
        rewardDebt.creatorStableRewardDebt = rewardDebt.creatorStableRewardDebt.add(rewards1);
    }

    function updateVoteRewardDetail(
        address user,
        uint256 poolId,
        uint256 rewards0,
        uint256 rewards1
    ) internal {
        rewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewardDebt.voterIpiStrRewardDebt = rewardDebt.voterIpiStrRewardDebt.add(rewards0);
        rewardDebt.voterStableRewardDebt = rewardDebt.voterStableRewardDebt.add(rewards1);
    }

    function updatePoolRewardDetail(
        address user,
        uint256 poolId,
        uint256 amount
    ) internal {
        poolInfo storage pool = poolInfoMap[poolId];
        rewardDebtInfo storage rewardDebt = rewardDebtInfoMap[poolId][user];
        rewardDebt.poolIpiStrRewardDebt = amount.mul(pool.accIPISTRPerShare).div(IPISTR_DECIMAL_SCALER);
        rewardDebt.poolStableRewardDebt = amount.mul(pool.accStablePerShare).div(IPISTR_DECIMAL_SCALER);
    }

    function getPools() internal view returns (uint256[] memory _poodIds) {
        _poodIds = poolGuardian.getPoolIds();
    }

    function getStrPool(uint256 poolId) public view returns (address strToken) {
        (, strToken, ) = poolGuardian.getPoolInfo(poolId);
    }

    function getForShares(address account, uint256 poolId) internal view returns (uint256 voteShare, uint256 totalShare) {
        (voteShare, totalShare) = committee.getForShares(account, poolId);
    }

    function setAllocPoint(uint256[] calldata _poolIds, uint256[] calldata _allocPoints) external isManager {
        require(_poolIds.length == _allocPoints.length, "PoolRewardModel: Invalid params");
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
            updatePool(_poolIds[i]);
        }
    }

    function setIpistrPerBlock(uint256 _ipistrPerBlock) external isManager {
        uint256[] memory onlinePools = poolGuardian.queryPools(address(0), IPoolGuardian.PoolStatus.RUNNING);
        for (uint256 i = 0; i < onlinePools.length; i++) {
            updatePool(onlinePools[i]);
        }
        ipistrPerBlock = _ipistrPerBlock;
    }

    function _getBefPoolWeight(uint256 _poolId) internal view returns (uint256 _befPoolWeight) {
        _befPoolWeight = uint256(poolInfoMap[_poolId].allocPoint).mul(poolInfoMap[_poolId].multiplier);
    }

    function initialize(
        address _shorterBone,
        address _poolGuardian,
        address _priceOracle,
        address _ipistrToken,
        address _committee,
        address _farming
    ) public isKeeper {
        require(!_initialized, "PoolRewardModel: Already initialized");
        ipistrPerBlock = 1e19;
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
        priceOracle = IPriceOracle(_priceOracle);
        committee = ICommittee(_committee);
        ipistrToken = _ipistrToken;
        farming = _farming;
        _initialized = true;
    }
}
