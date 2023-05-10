// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/AllyLibrary.sol";
import "../interfaces/IWETH.sol";
import "../../contracts/oracles/IPriceOracle.sol";
import "../interfaces/governance/ICommittee.sol";
import "../interfaces/v1/model/IInterestRateModel.sol";
import "../interfaces/IDexCenter.sol";
import "../criteria/ChainSchema.sol";
import "../storage/PoolStorage.sol";
import "../tokens/ERC20.sol";

contract PoolScatter is ChainSchema, PoolStorage, ERC20 {
    using AllyLibrary for IShorterBone;
    using SafeToken for ISRC20;

    /// @notice Emitted when user increase margin
    event IncreaseMargin(address indexed trader, address indexed position, uint256 amount);

    uint256 public maxCapacity;
    mapping(address => uint256) public positionOpenPriceMap;
    uint256 public poolCreationFee;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    modifier onlyTradingHub() {
        shorterBone.assertCaller(msg.sender, AllyLibrary.TRADING_HUB);
        _;
    }

    modifier onlyAuctionHall() {
        shorterBone.assertCaller(msg.sender, AllyLibrary.AUCTION_HALL);
        _;
    }

    modifier onlyAuction() {
        require(shorterBone.checkCaller(msg.sender, AllyLibrary.AUCTION_HALL) || shorterBone.checkCaller(msg.sender, AllyLibrary.VAULT_BUTLER), "PoolScatter: Caller is neither AuctionHall nor VaultButler");
        _;
    }

    modifier onlyRuler() {
        ICommittee committee = ICommittee(shorterBone.getModule(AllyLibrary.COMMITTEE));
        require(committee.isRuler(tx.origin), "PoolScatter: Caller is not ruler");
        _;
    }

    function borrow(address trader, address position, address dexcenter, uint256 amountIn, uint256 amountOutMin, bytes calldata data) external onlyTradingHub returns (uint256 amountOut) {
        _updateFundingFee(position);

        {
            wrapRouter.unwrap(id, address(stakedToken), address(this), amountIn, amountIn);
            shorterBone.poolTillOut(id, address(stakedToken), dexcenter, amountIn);
            uint256 amount0 = stableToken.balanceOf(address(this));
            (bool success, bytes memory returnData) = dexcenter.call(data);
            require(success, "PoolScatter: Transaction execution reverted");
            require(abi.decode(returnData, (uint256)) == amountIn, "PoolScatter: Invaild amountIn");
            amountOut = stableToken.balanceOf(address(this)).sub(amount0);
            require(amountOut > amountOutMin, "PoolScatter: Insufficient output amount");
        }

        PositionInfo storage positionInfo = positionInfoMap[position];
        uint256 marginAmount = amountOut.div(leverage);
        uint256 changePositionFee = amountOut.mul(getInterestRate(trader)).div(1e6);
        shorterBone.poolTillIn(id, address(stableToken), trader, marginAmount.add(changePositionFee));
        shorterBone.poolRevenue(id, trader, address(stableToken), changePositionFee, IShorterBone.IncomeType.TRADING_FEE);
        uint256 unsettledCash = amountOut.add(marginAmount);

        if (positionInfo.trader == address(0)) {
            require(amountOut > 10 ** (uint256(stableTokenDecimals).add(1)), "PoolScatter: Too small position value");
            positionInfo.trader = trader;
            positionInfo.totalSize = amountIn;
            positionInfo.unsettledCash = unsettledCash;
        } else {
            positionInfo.totalSize = positionInfo.totalSize.add(amountIn);
            positionInfo.unsettledCash = positionInfo.unsettledCash.add(unsettledCash);
        }

        updateOpenPrice(position);
        _updateTradingFee(trader, changePositionFee);
        tradingVolumeOf[trader] = tradingVolumeOf[trader].add(amountOut);
        totalBorrowAmount = totalBorrowAmount.add(amountIn);
    }

    function repay(address trader, address position, address dexcenter, uint256 amountOut, uint256 amountInMax, bytes calldata data) external onlyTradingHub returns (bool isClosed) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        require(positionInfo.totalSize >= amountOut, "PoolScatter: Invalid amountOut");
        require(positionInfo.trader == trader, "PoolGarner: Caller is not trader");

        _updateFundingFee(position);

        if (positionInfo.unsettledCash.mul(positionInfo.totalSize.sub(amountOut)).div(positionInfo.totalSize) < 10 ** (uint256(stableTokenDecimals))) {
            amountInMax = positionInfo.unsettledCash;
            amountOut = positionInfo.totalSize;
        }

        uint256 _amountInMax = positionInfo.unsettledCash.mul(amountOut).div(positionInfo.totalSize);
        require(_amountInMax >= amountInMax, "PoolScatter: Invalid amountInMax");

        uint256 amountIn;
        {
            uint256 amount0 = stakedToken.balanceOf(address(this));
            uint256 amount1 = stableToken.balanceOf(address(this));

            shorterBone.poolTillOut(id, address(stableToken), dexcenter, amountInMax);
            (bool success, ) = dexcenter.call(data);
            require(success, "PoolScatter: Transaction execution reverted");
            require(stakedToken.balanceOf(address(this)) >= amountOut.add(amount0), "PoolScatter: Insufficient output amount");

            amountIn = amount1.sub(stableToken.balanceOf(address(this)));
            wrapRouter.wrap(id, address(stakedToken), address(this), amountOut, address(stakedToken));
        }

        uint256 changePositionFee = amountIn.mul(getInterestRate(trader)).div(1e6);

        shorterBone.poolRevenue(id, trader, address(stableToken), changePositionFee, IShorterBone.IncomeType.TRADING_FEE);
        shorterBone.poolTillOut(id, address(stableToken), trader, _amountInMax.sub(amountIn).sub(changePositionFee));

        isClosed = amountOut == positionInfo.totalSize;
        if (!isClosed) {
            positionInfo.totalSize = positionInfo.totalSize.sub(amountOut);
            positionInfo.unsettledCash = positionInfo.unsettledCash.sub(_amountInMax);
            updateOpenPrice(position);
        }

        _updateTradingFee(trader, changePositionFee);

        tradingVolumeOf[trader] = tradingVolumeOf[trader].add(amountIn);
        totalBorrowAmount = totalBorrowAmount.sub(amountOut);
    }

    function increaseMargin(address position, address trader, uint256 amount) external whenNotPaused onlyTradingHub {
        PositionInfo storage positionInfo = positionInfoMap[position];
        require(positionInfo.trader == trader, "PoolGarner: Caller is not trader");
        shorterBone.poolTillIn(id, address(stableToken), trader, amount);
        positionInfo.unsettledCash = positionInfo.unsettledCash.add(amount);
        emit IncreaseMargin(trader, position, amount);
    }

    function auctionClosed(address position, uint256 phase1Used, uint256 phase2Used) external onlyAuction {
        PositionInfo storage positionInfo = positionInfoMap[position];
        if (phase1Used > 0 || phase2Used > 0) {
            wrapRouter.wrap(id, address(stakedToken), address(this), positionInfo.totalSize, address(stakedToken));
            totalBorrowAmount = totalBorrowAmount.sub(positionInfo.totalSize);
        }
        positionInfo.closedFlag = true;
        positionInfo.remnantAsset = positionInfo.unsettledCash.sub(phase1Used).sub(phase2Used);
    }

    function dexCover(address dexCenter, uint256 amountOut, uint256 amountInMax, bytes calldata data) external onlyAuctionHall returns (uint256 amountIn, uint256 rewards) {
        uint256 amount0 = stakedToken.balanceOf(msg.sender);
        uint256 amount1 = stableToken.balanceOf(address(this));

        shorterBone.poolTillOut(id, address(stableToken), dexCenter, amountInMax);
        (bool success, ) = dexCenter.call(data);
        require(success, "PoolScatter: Transaction execution reverted");

        require(stakedToken.balanceOf(address(msg.sender)) >= amountOut.add(amount0), "PoolScatter: Insufficient output amount");
        amountIn = amount1.sub(stableToken.balanceOf(address(this)));
        rewards = amountInMax.sub(amountIn);
    }

    function getPositionLiquidationPrice(address position) external view returns (uint256 liquidationPrice) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        uint256 fundingFee = getFundingFee(position);
        uint256 availableAmount = positionInfo.unsettledCash > fundingFee ? positionInfo.unsettledCash.sub(fundingFee) : 0;
        uint256 overdrawnPrice = availableAmount.mul(10 ** (uint256(stakedTokenDecimals).add(18).sub(uint256(stableTokenDecimals)))).div(positionInfo.totalSize);
        liquidationPrice = overdrawnPrice.mul(uint256(leverage).mul(100).add(70)).div(uint256(leverage).mul(100).add(100));
    }

    function updateOpenPrice(address position) internal {
        PositionInfo storage positionInfo = positionInfoMap[position];
        require(positionInfo.unsettledCash > 0 && positionInfo.totalSize > 0, "PoolScatterV3: Position is closed");
        uint256 overdrawnPrice = positionInfo.unsettledCash.mul(10 ** (uint256(18).add(stakedTokenDecimals).sub(stableTokenDecimals))).div(positionInfo.totalSize);
        positionOpenPriceMap[position] = overdrawnPrice.mul(uint256(leverage).mul(100)).div(uint256(leverage).mul(100).add(100));
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

    function _updateFundingFee(address position) internal {
        PositionInfo storage positionInfo = positionInfoMap[position];
        if (positionInfo.lastestFeeBlock == 0) {
            positionInfo.lastestFeeBlock = block.number.to64();
            return;
        }
        uint256 _totalFee = getFundingFee(position);
        shorterBone.poolRevenue(id, positionInfo.trader, address(stableToken), _totalFee, IShorterBone.IncomeType.FUNDING_FEE);
        positionInfo.totalFee = positionInfo.totalFee.add(_totalFee);
        positionInfo.unsettledCash = positionInfo.unsettledCash > _totalFee ? positionInfo.unsettledCash.sub(_totalFee) : 0;
        positionInfo.lastestFeeBlock = block.number.to64();
        _updateTradingFee(positionInfo.trader, _totalFee);
    }

    function getInterestRate(address account) public view returns (uint256) {
        uint256 multiplier = tradingVolumeOf[account].div(uint256(20000).mul(10 ** uint256(stableTokenDecimals)));
        return multiplier < 5 ? uint256(3000).sub(multiplier.mul(300)) : 1500;
    }

    function getFundingFee(address position) public view returns (uint256 totalFee_) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        uint256 blockSpan = block.number.sub(uint256(positionInfo.lastestFeeBlock));
        uint256 borrowAmount = positionOpenPriceMap[position].mul(positionInfo.totalSize).div(10 ** (uint256(18).add(stakedTokenDecimals).sub(stableTokenDecimals)));
        uint256 fundingFeePerBlock = IInterestRateModel(shorterBone.getInterestRateModel()).getBorrowRate(id, borrowAmount);
        totalFee_ = fundingFeePerBlock.mul(blockSpan).div(1e6);
    }

    function queryBorrowInfo() public view returns (uint256 debtAmount, uint256 unsettledCash) {
        debtAmount = totalBorrowAmount;
        unsettledCash = stableTokenAmountLeftover;
    }

    function stableTillOut(address bidder, uint256 amount) external {
        shorterBone.assertCaller(msg.sender, AllyLibrary.AUCTION_HALL);
        shorterBone.poolTillOut(id, address(stableToken), bidder, amount);
    }

    function takeLegacyStableToken(address bidder, address position, uint256 amount, uint256 takeSize) external payable {
        shorterBone.assertCaller(msg.sender, AllyLibrary.VAULT_BUTLER);
        if (address(stakedToken) == WrappedEtherAddr) {
            require(msg.value == takeSize, "PoolScatter: Invalid ether amount");
            IWETH(WrappedEtherAddr).deposit{value: msg.value}();
        } else {
            shorterBone.poolTillIn(id, address(stakedToken), bidder, takeSize);
        }
        wrapRouter.wrap(id, address(stakedToken), address(this), takeSize, address(stakedToken));
        totalBorrowAmount = totalBorrowAmount.sub(takeSize);
        PositionInfo storage positionInfo = positionInfoMap[position];
        positionInfo.unsettledCash = positionInfo.unsettledCash.sub(amount);
        positionInfo.totalSize = positionInfo.totalSize.sub(takeSize);
        shorterBone.poolTillOut(id, address(stableToken), bidder, amount);
    }

    function batchUpdateFundingFee(address[] calldata positions) external onlyTradingHub {
        for (uint256 i = 0; i < positions.length; i++) {
            _updateFundingFee(positions[i]);
        }
    }

    function markLegacy(address[] calldata positions) external onlyTradingHub {
        uint256 positionSize = positions.length;
        for (uint256 i = 0; i < positionSize; i++) {
            stableTokenAmountLeftover = stableTokenAmountLeftover.add(positionInfoMap[positions[i]].unsettledCash);
        }
        isLegacyLeftover = true;
    }

    function withdrawRemnantAsset(address position) external {
        PositionInfo storage positionInfo = positionInfoMap[position];
        require(msg.sender == positionInfo.trader, "PoolScatter: Caller is not the trader");
        shorterBone.poolTillOut(id, address(stableToken), msg.sender, positionInfo.remnantAsset);
        positionInfo.remnantAsset = 0;
    }

    function updatePositionToAuctionHall(address position) external onlyTradingHub returns (uint256 positionState) {
        uint256 currentPrice = IPriceOracle(shorterBone.getPriceOracle()).quote(address(stakedToken), address(stableToken));
        positionState = estimatePositionState(currentPrice, position);
        if (positionState != 1) {
            _updateFundingFee(position);
        }
    }

    function getPositionAssetInfo(address position) external view returns (uint256 totalSize, uint256 unsettledCash) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        return (positionInfo.totalSize, positionInfo.unsettledCash);
    }

    function estimatePositionState(uint256 currentPrice, address position) public view returns (uint256) {
        PositionInfo storage positionInfo = positionInfoMap[position];
        uint256 fundingFee = getFundingFee(position);
        uint256 availableAmount = positionInfo.unsettledCash > fundingFee ? positionInfo.unsettledCash.sub(fundingFee) : 0;
        uint256 overdrawnPrice = availableAmount.mul(10 ** (uint256(stakedTokenDecimals).add(18).sub(uint256(stableTokenDecimals)))).div(positionInfo.totalSize);
        if (currentPrice > overdrawnPrice) {
            return 4;
        }
        uint256 liquidationPrice = overdrawnPrice.mul(uint256(leverage).mul(100).add(70)).div(uint256(leverage).mul(100).add(100));
        if (currentPrice > liquidationPrice) {
            return 2;
        }

        return 1;
    }
}
