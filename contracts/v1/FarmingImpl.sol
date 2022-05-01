// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/AllyLibrary.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityAmounts.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/uniswapv3/IUniswapV3Pool.sol";
import "../interfaces/uniswapv3/INonfungiblePositionManager.sol";
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

contract FarmingImpl is ChainSchema, FarmingStorage, IFarming {
    using SafeToken for ISRC20;
    using BoringMath for uint256;

    mapping (uint256 => mapping(address => UserInfo)) public tokenUserInfoMap;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    // amountA: Uniswap pool token0 Amount
    // amountB: Uniswap pool token1 Amount
    function stake(
        uint256 tokenId,
        uint256 amountA,
        uint256 amountB,
        uint256 minLiquidity
    ) external whenNotPaused onlyEOA returns (uint256 liquidity) {
        require(tokenId == _tokenId, "Farming: Invalid tokenId");
        _updatePool(tokenId);
        PoolInfo storage pool = poolInfoMap[tokenId];
        (, uint256 token0Reward, uint256 token1Reward) = getUserInfo(msg.sender, tokenId);
        if (token0Reward > 0) {
            shorterBone.tillOut(pool.token0, AllyLibrary.FARMING, msg.sender, token0Reward);
        }
        if (token1Reward > 0) {
            shorterBone.tillOut(pool.token1, AllyLibrary.FARMING, msg.sender, token1Reward);
        }
        shorterBone.tillIn(pool.token0, msg.sender, AllyLibrary.FARMING, amountA);
        shorterBone.tillIn(pool.token1, msg.sender, AllyLibrary.FARMING, amountB);
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = INonfungiblePositionManager.IncreaseLiquidityParams({tokenId: tokenId, amount0Desired: amountA, amount1Desired: amountB, amount0Min: 0, amount1Min: 0, deadline: block.timestamp});
        (uint128 _liquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager.increaseLiquidity(increaseLiquidityParams);
        liquidity = uint256(_liquidity);
        require(liquidity > minLiquidity, "Farming: Slippage too large");
        farmingRewardModel.harvestByPool(msg.sender);
        UserInfo storage userInfo = tokenUserInfoMap[tokenId][msg.sender];
        userInfo.amount = userInfo.amount.add(liquidity);
        userInfo.token0Debt = pool.token0PerLp.mul(userInfo.amount).div(1e12);
        userInfo.token1Debt = pool.token1PerLp.mul(userInfo.amount).div(1e12);
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender].add(liquidity.mul(pool.midPrice.div(1e12)));
        emit Stake(msg.sender, tokenId, liquidity, amount0, amount1);
    }

    function unStake(
        uint256 tokenId,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) external whenNotPaused onlyEOA {
        UserInfo storage userInfo = tokenUserInfoMap[tokenId][msg.sender];
        require(userInfo.amount >= liquidity, "Farming: Invalid withdraw amount");
        _updatePool(tokenId);
        PoolInfo storage pool = poolInfoMap[tokenId];
        (, uint256 token0Reward, uint256 token1Reward) = getUserInfo(msg.sender, tokenId);
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager.DecreaseLiquidityParams({tokenId: tokenId, liquidity: uint128(liquidity), amount0Min: amount0Min, amount1Min: amount1Min, deadline: block.timestamp});
        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.decreaseLiquidity(decreaseLiquidityParams);
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({tokenId: tokenId, recipient: address(this), amount0Max: uint128(amount0), amount1Max: uint128(amount1)});
        (amount0, amount1) = nonfungiblePositionManager.collect(collectParams);
        farmingRewardModel.harvestByPool(msg.sender);
        userInfo.amount = userInfo.amount.sub(liquidity);
        userInfo.token0Debt = pool.token0PerLp.mul(userInfo.amount).div(1e12);
        userInfo.token1Debt = pool.token1PerLp.mul(userInfo.amount).div(1e12);
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender].sub(liquidity.mul(pool.midPrice.div(1e12)));
        shorterBone.tillOut(pool.token0, AllyLibrary.FARMING, msg.sender, amount0.add(token0Reward));
        shorterBone.tillOut(pool.token1, AllyLibrary.FARMING, msg.sender, amount1.add(token1Reward));
        emit UnStake(msg.sender, tokenId, liquidity, amount0, amount1);
    }

    function _updatePool(uint256 tokenId) internal {
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({tokenId: tokenId, recipient: address(this), amount0Max: uint128(0) - 1, amount1Max: uint128(0) - 1});
        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.collect(collectParams);
        (, , , , , , , uint128 _liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
        if (_liquidity > 0) {
            PoolInfo storage pool = poolInfoMap[tokenId];
            pool.token0PerLp = pool.token0PerLp.add(amount0.mul(1e12).div(uint256(_liquidity)));
            pool.token1PerLp = pool.token1PerLp.add(amount1.mul(1e12).div(uint256(_liquidity)));
        }
    }

    function getUserInfo(address user, uint256 tokenId)
        public
        view
        returns (
            uint256 stakedAmount,
            uint256 token0Rewards,
            uint256 token1Rewards
        )
    {
        UserInfo storage userInfo = tokenUserInfoMap[tokenId][user];
        PoolInfo storage pool = poolInfoMap[tokenId];
        stakedAmount = userInfo.amount;
        if (stakedAmount > 0) {
            (, , , , , , , uint128 _liquidity, , , uint256 tokensOwed0, uint256 tokensOwed1) = nonfungiblePositionManager.positions(tokenId);
            uint256 token0PerLp = pool.token0PerLp.add(tokensOwed0.mul(1e12).div(uint256(_liquidity)));
            uint256 token1PerLp = pool.token1PerLp.add(tokensOwed1.mul(1e12).div(uint256(_liquidity)));
            token0Rewards = (token0PerLp.mul(stakedAmount).div(1e12)).sub(userInfo.token0Debt);
            token1Rewards = (token1PerLp.mul(stakedAmount).div(1e12)).sub(userInfo.token1Debt);
        }
    }

    function getUserStakedAmount(address user) external view override returns (uint256 userStakedAmount_) {
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

    function getAmountsForLiquidity(uint256 tokenId, uint128 liquidity)
        public
        view
        returns (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1
        )
    {
        uint160 sqrtRatioX96;
        uint160 sqrtRatioAX96;
        uint160 sqrtRatioBX96;
        (sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, token0, token1) = _getSqrtRatioByTokenId(tokenId);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function _getSqrtRatioByTokenId(uint256 tokenId)
        internal
        view
        returns (
            uint160 sqrtRatioX96,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96,
            address token0,
            address token1
        )
    {
        int24 tickLower;
        int24 tickUpper;
        (, , token0, token1, , tickLower, tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenId);
        (sqrtRatioX96, , , , , , ) = uniswapV3Pool.slot0();
        sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    function getBaseAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) external pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int256 tick) {
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function getSqrtRatioAtTick(int24 tick) external pure returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
    }

    function setRewardModel(
        address _tradingRewardModel,
        address _farmingRewardModel,
        address _govRewardModel,
        address _poolRewardModel,
        address _voteRewardModel
    ) external isKeeper {
        tradingRewardModel = ITradingRewardModel(_tradingRewardModel);
        farmingRewardModel = IFarmingRewardModel(_farmingRewardModel);
        govRewardModel = IGovRewardModel(_govRewardModel);
        poolRewardModel = IPoolRewardModel(_poolRewardModel);
        voteRewardModel = IVoteRewardModel(_voteRewardModel);
    }

    function setNonfungiblePositionManager(
        INonfungiblePositionManager _nonfungiblePositionManager,
        IUniswapV3Pool _uniswapV3Pool,
        address _ipistrToken
    ) external isKeeper {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        ipistrToken = _ipistrToken;
        uniswapV3Pool = _uniswapV3Pool;
    }

    function createPool(INonfungiblePositionManager.MintParams calldata params) external isManager returns (uint256) {
        shorterBone.tillIn(params.token0, msg.sender, AllyLibrary.FARMING, params.amount0Desired);
        shorterBone.tillIn(params.token1, msg.sender, AllyLibrary.FARMING, params.amount1Desired);
        (uint256 tokenId, uint128 liquidity, , ) = nonfungiblePositionManager.mint(params);
        uint256 midPrice = _setPoolInfo(tokenId);
        UserInfo storage userInfo = tokenUserInfoMap[tokenId][msg.sender];
        userInfo.amount = userInfo.amount.add(uint256(liquidity));
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender].add(uint256(liquidity).mul(midPrice.div(1e12)));
    }

    function getTokenInfo(uint256 tokenId)
        public
        view
        returns (
            uint256 lowerPrice,
            uint256 upperPrice,
            uint256 midPrice,
            uint256 fee,
            uint256 liquidity
        )
    {
        (, , address token0, address token1, uint24 _fee, int24 tickLower, int24 tickUpper, uint128 _liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
        int24 midTick = (tickUpper >> 1) + (tickLower >> 1);
        uint160 sqrtMPriceX96 = TickMath.getSqrtRatioAtTick(midTick);
        uint160 sqrtAPriceX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtBPriceX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        lowerPrice = getPirceBySqrtPriceX96(sqrtAPriceX96, token0, token1, ipistrToken);
        upperPrice = getPirceBySqrtPriceX96(sqrtBPriceX96, token0, token1, ipistrToken);
        midPrice = getPirceBySqrtPriceX96(sqrtMPriceX96, token0, token1, ipistrToken);
        fee = uint256(_fee);
        liquidity = uint256(_liquidity);
    }

    function getPirceBySqrtPriceX96(
        uint160 sqrtPriceX96,
        address token0,
        address token1,
        address quoteToken
    ) public view returns (uint256 price) {
        uint256 token0Decimals = uint256(ISRC20(token0).decimals());
        uint256 token1Decimals = uint256(ISRC20(token1).decimals());
        uint256 token0Price;
        uint256 sqrtDecimals = uint256(18).add(token0Decimals).sub(token1Decimals).div(2);
        if (sqrtDecimals.mul(2) == uint256(18).add(token0Decimals).sub(token1Decimals)) {
            uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10**sqrtDecimals).div(2**96);
            token0Price = sqrtPrice.mul(sqrtPrice);
        } else {
            uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10**(sqrtDecimals + 1)).div(2**96);
            token0Price = sqrtPrice.mul(sqrtPrice).div(10);
        }
        if (token0 == quoteToken) {
            price = token0Price;
        } else {
            price = uint256(1e36).div(token0Price);
        }
    }

    function setTokenId(uint256 tokenId) external isKeeper {
        _tokenId = tokenId;
    }

    function getTokenId() external view override returns (uint256) {
        return _tokenId;
    }

    function setPoolInfo(uint256 tokenId) external isKeeper {
        _setPoolInfo(tokenId);
    }

    function initialize(address _shorterBone) external isSavior {
        require(!_initialized, "Farming: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        _initialized = true;
    }

    function harvest(uint256 tokenId, address user) external override {
        require(msg.sender == address(farmingRewardModel), "Farming: Caller is not FarmingRewardModel");
        _updatePool(tokenId);
        PoolInfo storage pool = poolInfoMap[tokenId];
        (, uint256 token0Reward, uint256 token1Reward) = getUserInfo(user, tokenId);
        if (token0Reward > 0) {
            shorterBone.tillOut(pool.token0, AllyLibrary.FARMING, user, token0Reward);
        }
        if (token1Reward > 0) {
            shorterBone.tillOut(pool.token1, AllyLibrary.FARMING, user, token1Reward);
        }

        UserInfo storage userInfo = tokenUserInfoMap[tokenId][user];
        userInfo.token0Debt = pool.token0PerLp.mul(userInfo.amount).div(1e12);
        userInfo.token1Debt = pool.token1PerLp.mul(userInfo.amount).div(1e12);
    }

    function _setPoolInfo(uint256 tokenId) internal returns (uint256 midPrice) {
        (, , address token0, address token1, uint24 _fee, int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenId);
        int24 midTick = (tickUpper >> 1) + (tickLower >> 1);
        uint160 sqrtMPriceX96 = TickMath.getSqrtRatioAtTick(midTick);
        uint160 sqrtAPriceX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtBPriceX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        uint256 lowerPrice;
        uint256 upperPrice;
        (lowerPrice, upperPrice, midPrice) = _getLpPriceInfo(sqrtMPriceX96, sqrtAPriceX96, sqrtBPriceX96, token0, token1);
        poolInfoMap[tokenId] = PoolInfo({token0: token0, token1: token1, fee: uint256(_fee), midPrice: midPrice, lowerPrice: lowerPrice, upperPrice: upperPrice, token0PerLp: 0, token1PerLp: 0});
    }

    function _getLpPriceInfo(
        uint160 sqrtMPriceX96,
        uint160 sqrtAPriceX96,
        uint160 sqrtBPriceX96,
        address token0,
        address token1
    )
        internal
        view
        returns (
            uint256 lowerPrice,
            uint256 upperPrice,
            uint256 midPrice
        )
    {
        uint256 price0 = getPirceBySqrtPriceX96(sqrtAPriceX96, token0, token1, ipistrToken);
        uint256 price1 = getPirceBySqrtPriceX96(sqrtBPriceX96, token0, token1, ipistrToken);
        midPrice = getPirceBySqrtPriceX96(sqrtMPriceX96, token0, token1, ipistrToken);
        lowerPrice = price0 > price1 ? price1 : price0;
        upperPrice = price0 > price1 ? price0 : price1;
    }
}
