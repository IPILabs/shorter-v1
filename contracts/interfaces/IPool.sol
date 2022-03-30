// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./v1/IPoolGuardian.sol";
import "./v1/ITradingHub.sol";

interface IPool {
    function initialize(
        address creator,
        address stakedToken,
        address stableToken,
        address wrapRouter,
        address _tradingHub,
        address _poolRewardModel,
        uint256 poolId,
        uint256 leverage,
        uint256 durationDays,
        uint256 blocksPerDay,
        address wrappedEtherAddr
    ) external;

    function setStateFlag(IPoolGuardian.PoolStatus newStateFlag) external;

    function list() external;

    function getInfo()
        external
        view
        returns (
            address creator,
            address stakedToken,
            address stableToken,
            address wrappedToken,
            uint256 leverage,
            uint256 durationDays,
            uint256 startBlock,
            uint256 endBlock,
            uint256 id,
            uint256 stakedTokenDecimals,
            uint256 stableTokenDecimals,
            IPoolGuardian.PoolStatus stateFlag
        );

    function borrow(
        bool isSwapRouterV3,
        address dexCenter,
        address swapRouter,
        address position,
        address trader,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory path
    ) external returns (uint256 amountOut);

    function repay(
        bool isSwapRouterV3,
        bool isTetherToken,
        address dexCenter,
        address swapRouter,
        address position,
        address trader,
        uint256 amountOut,
        uint256 amountInMax,
        bytes memory path
    ) external returns (bool isClosed);

    function updatePositionToAuctionHall(address position) external returns (ITradingHub.PositionState positionState);

    function getPositionInfo(address position) external view returns (uint256 totalSize, uint256 unsettledCash);

    function dexCover(
        bool isSwapRouterV3,
        bool isTetherToken,
        address dexCenter,
        address swapRouter,
        uint256 amountOut,
        uint256 amountInMax,
        bytes memory path
    ) external returns (uint256 amountIn);

    function auctionClosed(
        address position,
        uint256 phase1Used,
        uint256 phase2Used,
        uint256 legacyUsed
    ) external;

    function batchUpdateFundingFee(address[] memory positions) external;

    function delivery(bool _isLegacyLeftover) external;

    function stableTillOut(address bidder, uint256 amount) external;

    function tradingFeeOf(address trader) external view returns (uint256);

    function totalTradingFee() external view returns (uint256);

    function currentRound() external view returns (uint256);

    function currentRoundTradingFeeOf(address trader) external view returns (uint256);

    function estimatePositionState(uint256 currentPrice, address position) external view returns (ITradingHub.PositionState);
}
