// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./v1/IPoolGuardian.sol";
import "./v1/ITradingHub.sol";

interface IPool {
    struct CreatePoolParams {
        address stakedToken;
        address stableToken;
        address creator;
        uint256 leverage;
        uint256 durationDays;
        uint256 poolId;
        uint256 maxCapacity;
        uint256 poolCreationFee;
    }

    function initialize(address _wrapRouter, address _tradingHubAddr, address _poolRewardModelAddr, uint256 __blocksPerDay, address _WrappedEtherAddr, CreatePoolParams calldata _createPoolParams) external;

    function setStateFlag(IPoolGuardian.PoolStatus newStateFlag) external;

    function list() external;

    function getMetaInfo()
        external
        view
        returns (address creator, address stakedToken, address stableToken, address wrappedToken, uint256 leverage, uint256 durationDays, uint256 startBlock, uint256 endBlock, uint256 id, uint256 stakedTokenDecimals, uint256 stableTokenDecimals, IPoolGuardian.PoolStatus stateFlag);

    function borrow(address trader, address position, address dexcenter, uint256 amountIn, uint256 amountOutMin, bytes calldata data) external returns (uint256 amountOut);

    function repay(address trader, address position, address dexcenter, uint256 amountOut, uint256 amountInMax, bytes calldata data) external returns (bool isClosed);

    function updatePositionToAuctionHall(address position) external returns (uint256 positionState);

    function getPositionAssetInfo(address position) external view returns (uint256 totalSize, uint256 unsettledCash);

    function dexCover(address dexCenter, uint256 amountOut, uint256 amountInMax, bytes calldata data) external returns (uint256 amountIn, uint256 rewards);

    function auctionClosed(address position, uint256 phase1Used, uint256 phase2Used) external;

    function batchUpdateFundingFee(address[] calldata positions) external;

    function markLegacy(address[] calldata positions) external;

    function stableTillOut(address bidder, uint256 amount) external;

    function takeLegacyStableToken(address bidder, address position, uint256 amount, uint256 takeSize) external payable;

    function tradingFeeOf(address trader) external view returns (uint256);

    function totalTradingFee() external view returns (uint256);

    function currentRound() external view returns (uint256);

    function currentRoundTradingFeeOf(address trader) external view returns (uint256);

    function estimatePositionState(uint256 currentPrice, address position) external view returns (uint256);

    function increaseMargin(address position, address trader, uint256 amount) external;

    function poolCreationFee() external view returns (uint256);
}
