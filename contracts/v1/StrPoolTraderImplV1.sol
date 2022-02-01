// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IDexCenter.sol";
import "../criteria/Affinity.sol";
import "../storage/StrPoolStorage.sol";
import "../tokens/ERC20.sol";

contract StrPoolTraderImplV1 is Affinity, Pausable, StrPoolStorage, ERC20 {
    modifier onlyTradingHub() {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.TRADING_HUB), "StrPool: Caller is not TradingHub");
        _;
    }

    modifier onlyAuction() {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.AUCTION_HALL) || msg.sender == shorterBone.getAddress(AllyLibrary.VAULT_BUTLER), "StrPool: Caller is neither auctionHall nor vaultButler");
        _;
    }

    constructor(address _SAVIOR) public Affinity(_SAVIOR) {}

    function borrow(
        bool isSwapRouterV3,
        address dexCenter,
        address swapRouter,
        address position,
        address trader,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory path
    ) external onlyTradingHub returns (uint256 amountOut) {
        _updateFunding(position);

        IWrapRouter(wrapRouter).unwrap(address(stakedToken), amountIn);
        totalStakedTokenAmount = totalStakedTokenAmount.sub(amountIn);
        bytes memory data = delegateTo(dexCenter, abi.encodeWithSignature("sellShort((bool,uint256,uint256,address,address,bytes))", IDexCenter.SellShortParams({isSwapRouterV3: isSwapRouterV3, amountIn: amountIn, amountOutMin: amountOutMin, swapRouter: swapRouter, to: address(this), path: path})));
        amountOut = abi.decode(data, (uint256));

        PositionInfo storage positionInfo = positionInfoMap[position];
        uint256 marginAmount = amountOut.div(leverage);
        uint256 unsettledCash = amountOut.mul(uint256(1e6).sub(getInterestRate(trader))).div(1e6).add(marginAmount);
        uint256 changePositionFee = amountOut.add(marginAmount).sub(unsettledCash);
        shorterBone.poolRevenue(id, trader, address(stableToken), changePositionFee, IShorterBone.IncomeType.TRADING_FEE);
        shorterBone.poolTillIn(id, address(stableToken), trader, marginAmount);

        if (positionInfo.trader == address(0)) {
            positionInfo.trader = trader;
            positionInfo.lastestFeeBlock = block.number.to64();
            positionInfo.totalSize = amountIn;
            positionInfo.unsettledCash = unsettledCash;
        } else {
            positionInfo.totalSize = positionInfo.totalSize.add(amountIn);
            positionInfo.unsettledCash = positionInfo.unsettledCash.add(unsettledCash);
        }

        tradingVolumeOf[trader] = tradingVolumeOf[trader].add(amountOut);
        _updateTradingFee(trader, changePositionFee);
    }

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
    ) external onlyTradingHub returns (bool isClosed) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        require(positionInfo.totalSize >= amountOut, "StrPool: Invalid amountOut");

        _updateFunding(position);
        uint256 _amountInMax = positionInfo.unsettledCash.mul(amountOut).div(positionInfo.totalSize);
        require(_amountInMax >= amountInMax, "StrPool: Invalid amountInMax");

        uint256 amountIn = buyCover(dexCenter, isSwapRouterV3, isTetherToken, amountOut, amountInMax, swapRouter, address(this), path);
        require(positionInfo.unsettledCash.sub(amountIn) > 10**uint256(stableTokenDecimals) || amountOut == positionInfo.totalSize, "StrPool: remaining position value is less than 1");
        uint256 changePositionFee = amountIn.mul(getInterestRate(trader)).div(1e6);

        shorterBone.poolRevenue(id, trader, address(stableToken), changePositionFee, IShorterBone.IncomeType.TRADING_FEE);
        shorterBone.poolTillOut(id, address(stableToken), trader, _amountInMax.sub(amountIn).sub(changePositionFee));

        isClosed = amountOut == positionInfo.totalSize;

        if (!isClosed) {
            uint256 remainingShare = (positionInfo.totalSize.sub(amountOut)).mul(1e18).div(positionInfo.totalSize);
            positionInfo.totalSize = positionInfo.totalSize.sub(amountOut);
            positionInfo.unsettledCash = positionInfo.unsettledCash.mul(remainingShare).div(1e18);
        }

        tradingVolumeOf[trader] = tradingVolumeOf[trader].add(amountIn);
        _updateTradingFee(trader, changePositionFee);
    }

    function auctionClosed(
        address position,
        uint256 phase1Used,
        uint256 phase2Used,
        uint256 legacyUsed
    ) external onlyAuction {
        PositionInfo storage positionInfo = positionInfoMap[position];
        IWrapRouter(wrapRouter).wrap(address(stakedToken), positionInfo.totalSize);
        totalStakedTokenAmount = totalStakedTokenAmount.add(positionInfo.totalSize);
        positionInfo.closedFlag = true;
        positionInfo.remnantAsset = positionInfo.unsettledCash.sub(phase1Used).sub(phase2Used).sub(legacyUsed);
    }

    function dexCover(
        bool isSwapRouterV3,
        bool isTetherToken,
        address dexCenter,
        address swapRouter,
        uint256 amountOut,
        uint256 amountInMax,
        bytes memory path
    ) external returns (uint256 amountIn) {
        address auctionHall = shorterBone.getAddress(AllyLibrary.AUCTION_HALL);
        require(msg.sender == auctionHall, "StrPool: Caller is not AuctionHall");
        amountIn = buyCover(dexCenter, isSwapRouterV3, isTetherToken, amountOut, amountInMax, swapRouter, auctionHall, path);
    }

    function stableTillOut(address bidder, uint256 amount) external onlyAuction {
        shorterBone.poolTillOut(id, address(stableToken), bidder, amount);
    }

    function batchUpdateFundingFee(address[] memory positions) external onlyTradingHub {
        for (uint256 i = 0; i < positions.length; i++) {
            _updateFunding(positions[i]);
        }
    }

    function delivery(bool _isDelivery) external onlyTradingHub {
        isDelivery = _isDelivery;
    }

    function withdrawRemnantAsset(address position) public {
        PositionInfo storage positionInfo = positionInfoMap[position];
        require(msg.sender == positionInfo.trader, "StrPool: Caller is not the trader");
        shorterBone.poolTillOut(id, address(stableToken), msg.sender, positionInfo.remnantAsset);
        positionInfo.remnantAsset = 0;
    }

    function updatePositionToAuctionHall(address position) external onlyTradingHub returns (ITradingHub.PositionState positionState) {
        (uint256 currentPrice, uint256 tokenDecimals) = AllyLibrary.getPriceOracle(shorterBone).getLatestMixinPrice(address(stakedToken));
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));

        positionState = estimatePositionState(currentPrice, position);
        if (positionState != ITradingHub.PositionState.OPEN) {
            _updateFunding(position);
        }
    }

    function buyCover(
        address dexCenter,
        bool isSwapRouterV3,
        bool isTetherToken,
        uint256 amountOut,
        uint256 amountInMax,
        address swapRouter,
        address to,
        bytes memory path
    ) internal returns (uint256 amountIn) {
        bytes memory data = delegateTo(
            dexCenter,
            abi.encodeWithSignature("buyCover((bool,bool,uint256,uint256,address,address,bytes))", IDexCenter.BuyCoverParams({isSwapRouterV3: isSwapRouterV3, isTetherToken: isTetherToken, amountOut: amountOut, amountInMax: amountInMax, swapRouter: swapRouter, to: to, path: path}))
        );
        amountIn = abi.decode(data, (uint256));
        IWrapRouter(wrapRouter).wrap(address(stakedToken), amountOut);
        totalStakedTokenAmount = totalStakedTokenAmount.add(amountOut);
    }

    function getFundingFee(address position) public view returns (uint256 totalFee_) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        uint256 blockSpan = block.number.sub(uint256(positionInfo.lastestFeeBlock));
        uint256 fundingFeePerBlock = AllyLibrary.getInterestRateModel(shorterBone).getBorrowRate(id, positionInfo.unsettledCash.mul(uint256(leverage)).div(uint256(leverage).add(1)));
        totalFee_ = fundingFeePerBlock.mul(blockSpan).div(1e6);
    }

    function getInterestRate(address account) public view returns (uint256) {
        uint256 multiplier = tradingVolumeOf[account].div(uint256(20000).mul(10**uint256(stableTokenDecimals)));
        return multiplier < 5 ? uint256(3000).sub(multiplier.mul(300)) : 1500;
    }

    function getPositionInfo(address position) external view returns (uint256 totalSize, uint256 unsettledCash) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        return (positionInfo.totalSize, positionInfo.unsettledCash);
    }

    function estimatePositionState(uint256 currentPrice, address position) public view returns (ITradingHub.PositionState) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        uint256 availableAmount = positionInfo.unsettledCash.sub(getFundingFee(position));
        uint256 overdrawnPrice = availableAmount.mul(10**(uint256(stakedTokenDecimals).add(18).sub(uint256(stableTokenDecimals)))).div(positionInfo.totalSize);
        if (currentPrice > overdrawnPrice) {
            return ITradingHub.PositionState.OVERDRAWN;
        }
        uint256 liquidationPrice = overdrawnPrice.mul(uint256(leverage).mul(100).add(70)).div(uint256(leverage).mul(100).add(100));
        if (currentPrice > liquidationPrice) {
            return ITradingHub.PositionState.CLOSING;
        }

        return ITradingHub.PositionState.OPEN;
    }

    function _updateFunding(address position) internal {
        PositionInfo storage positionInfo = positionInfoMap[position];
        if (positionInfo.lastestFeeBlock == 0) {
            positionInfo.lastestFeeBlock = block.number.to64();
            return;
        }
        uint256 _totalFee = getFundingFee(position);
        shorterBone.poolRevenue(id, positionInfo.trader, address(stableToken), _totalFee, IShorterBone.IncomeType.FUNDING_FEE);
        positionInfo.totalFee = positionInfo.totalFee.add(_totalFee);
        positionInfo.unsettledCash = positionInfo.unsettledCash.sub(_totalFee);
        positionInfo.lastestFeeBlock = block.number.to64();
        _updateTradingFee(positionInfo.trader, _totalFee);
    }

    function _updateTradingFee(address trader, uint256 fee) internal {
        totalTradingFee = totalTradingFee.add(fee);
        tradingFeeOf[trader] = tradingFeeOf[trader].add(fee);
        uint256 _currentRound = (block.timestamp.sub(331200)).div(604800);
        if (currentRound == _currentRound) {
            currentRoundTradingFeeOf[trader] = currentRoundTradingFeeOf[trader].add(fee);
            return;
        }
        currentRoundTradingFeeOf[trader] = fee;
        currentRound = _currentRound;
    }

    function delegateTo(address callee, bytes memory data) private returns (bytes memory) {
        (bool success, bytes memory returnData) = callee.delegatecall(data);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }
        return returnData;
    }
}
