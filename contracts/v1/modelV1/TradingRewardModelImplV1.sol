// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../libraries/AllyLibrary.sol";
import "../../interfaces/v1/model/ITradingRewardModel.sol";
import "../../interfaces/IStrPool.sol";
import "../../criteria/ChainSchema.sol";
import "../../storage/model/TradingRewardModelStorage.sol";
import "../../util/BoringMath.sol";
import "../Rescuable.sol";

contract TradingRewardModelImplV1 is Rescuable, ChainSchema, Pausable, TradingRewardModelStorage, ITradingRewardModel {
    using BoringMath for uint256;

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function initialize(
        address _shorterBone,
        address _poolGuardian,
        address _priceOracle,
        address _ipistrToken,
        address _farming
    ) public isKeeper {
        require(!_initialized, "TradingRewardModel: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
        priceOracle = IPriceOracle(_priceOracle);
        ipistrToken = _ipistrToken;
        farming = _farming;
        _initialized = true;
    }

    function harvest(address trader, uint256[] memory poolIds) external override returns (uint256 rewards) {
        require(poolIds.length > 0, "TradingReward: Invalid pool size");
        bool isTrader = trader == msg.sender;
        if (!isTrader) {
            require(msg.sender == farming, "TradingReward: Caller is not Farming");
        }

        uint256 pendingTradingFee;
        for (uint256 i = 0; i < poolIds.length; i++) {
            uint256 tradingFee = _getTradingFee(trader, poolIds[i]);
            require(tradingFee > 0, "TradingReward: Invalid poolIds");
            tradingRewardDebt[poolIds[i]][trader] = tradingRewardDebt[poolIds[i]][trader].add(tradingFee);
            pendingTradingFee = pendingTradingFee.add(tradingFee);
        }

        (uint256 currentPrice, uint256 tokenDecimals) = priceOracle.getLatestMixinPrice(ipistrToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));
        rewards = pendingTradingFee.mul(1e18).mul(2).div(currentPrice).div(5);

        if (isTrader) {
            shorterBone.mintByAlly(AllyLibrary.TRADING_REWARD, trader, rewards);
        }
    }

    function pendingReward(address trader) external view override returns (uint256 rewards, uint256[] memory poolIds) {
        uint256[] memory _poolIds = poolGuardian.getPoolIds();
        uint256 poolSize = _poolIds.length;
        uint256[] memory poolContainer = new uint256[](poolSize);

        uint256 resPoolCount;
        uint256 pendingTradingFee;
        for (uint256 i = 0; i < poolSize; i++) {
            uint256 tradingFee = _getTradingFee(trader, _poolIds[i]);
            if (tradingFee > 0) {
                pendingTradingFee = pendingTradingFee.add(tradingFee);
                poolContainer[resPoolCount++] = _poolIds[i];
            }
        }

        poolIds = new uint256[](resPoolCount);
        for (uint256 i = 0; i < resPoolCount; i++) {
            poolIds[i] = poolContainer[i];
        }

        (uint256 currentPrice, uint256 tokenDecimals) = priceOracle.getLatestMixinPrice(ipistrToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));

        rewards = pendingTradingFee.mul(1e18).mul(2).div(currentPrice).div(5);
    }

    function _getTradingFee(address trader, uint256 poolId) internal view returns (uint256 tradingFee) {
        (address strToken, uint256 stableTokenDecimals) = getStableTokenDecimals(poolId);
        tradingFee = IStrPool(strToken).tradingFeeOf(trader).mul(10**(uint256(18).sub(stableTokenDecimals)));
        uint256 currentRoundTradingFee = IStrPool(strToken).currentRoundTradingFeeOf(trader);
        tradingFee = tradingFee.sub(tradingRewardDebt[poolId][trader]).sub(currentRoundTradingFee);
    }

    function getStableTokenDecimals(uint256 poolId) internal view returns (address strToken, uint256 stableTokenDecimals) {
        (, strToken, ) = poolGuardian.getPoolInfo(poolId);
        (, , , , , , , , , , stableTokenDecimals, ) = IStrPool(strToken).getInfo();
    }
}
