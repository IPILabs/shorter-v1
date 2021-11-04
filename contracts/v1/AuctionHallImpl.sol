// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/AllyLibrary.sol";
import "../libraries/Path.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/v1/IAuctionHall.sol";
import "../interfaces/IDexCenter.sol";
import "../interfaces/IStrPool.sol";
import "../criteria/ChainSchema.sol";
import "../storage/ThemisStorage.sol";
import "../util/BoringMath.sol";
import "./Rescuable.sol";

contract AuctionHallImpl is Rescuable, ChainSchema, Pausable, ThemisStorage, IAuctionHall {
    using BoringMath for uint256;
    using SafeToken for ISRC20;
    using Path for bytes;

    modifier onlyRuler(address ruler) {
        require(committee.isRuler(ruler), "AuctionHall: Caller is not a ruler");
        _;
    }

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function bidTanto(
        address position,
        uint256 bidSize,
        uint256 priorityFee
    ) external whenNotPaused onlyRuler(msg.sender) {
        PositionInfo memory positionInfo = getPositionInfo(position);
        require(bidSize > 0 && bidSize <= positionInfo.totalSize, "AuctionHall: Invalid bidSize");
        require(positionInfo.positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");
        require(block.number.sub(positionInfo.closingBlock) <= phase1MaxBlock, "AuctionHall: Tanto is over");

        Phase1Info storage phase1Info = phase1Infos[position];
        phase1Info.bidSize = phase1Info.bidSize.add(bidSize);
        phase1Info.liquidationPrice = estimateAuctionPrice(positionInfo.unsettledCash, positionInfo.totalSize, positionInfo.stakedToken, positionInfo.stakedTokenDecimals, positionInfo.stableTokenDecimals);

        if (!phase1Info.flag && phase1Info.bidSize >= positionInfo.totalSize) {
            phase1Info.flag = true;
        }

        shorterBone.tillIn(positionInfo.stakedToken, msg.sender, AllyLibrary.AUCTION_HALL, bidSize);
        shorterBone.tillIn(ipistrToken, msg.sender, AllyLibrary.AUCTION_HALL, priorityFee);

        allPhase1BidRecords[position].push(BidItem({takeBack: false, bidBlock: block.number.to64(), bidder: msg.sender, bidSize: bidSize, priorityFee: priorityFee}));

        emit BidTanto(position, msg.sender, bidSize, priorityFee);
    }

    function bidKatana(address position, bytes memory path) external whenNotPaused onlyRuler(msg.sender) {
        PositionInfo memory positionInfo = getPositionInfo(position);
        require(path.getTokenIn() == address(positionInfo.stableToken), "AuctionHall: Invalid tokenIn");
        require(path.getTokenOut() == address(positionInfo.stakedToken), "AuctionHall: Invalid tokenOut");
        require(positionInfo.positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");
        require(block.number.sub(positionInfo.closingBlock) > phase1MaxBlock && block.number.sub(positionInfo.closingBlock) <= auctionMaxBlock, "AuctionHall: Katana is over");
        Phase1Info storage phase1Info = phase1Infos[position];
        require(!phase1Info.flag, "AuctionHall: Position was closed");

        Phase2Info storage phase2Info = phase2Infos[position];

        uint256 phase1UsedUnsettledCash = phase1Info.bidSize.mul(phase1Info.liquidationPrice).div(10**(positionInfo.stakedTokenDecimals.add(18).sub(positionInfo.stableTokenDecimals)));
        phase2Info.debtSize = positionInfo.totalSize.sub(phase1Info.bidSize);
        uint256 estimatePhase2UseCash = positionInfo.unsettledCash.sub(phase1UsedUnsettledCash);
        (, address swapRouter, ) = shorterBone.getTokenInfo(address(positionInfo.stakedToken));
        phase2Info.usedCash = IStrPool(positionInfo.strToken).dexCover(IDexCenter(dexCenter).isSwapRouterV3(swapRouter), shorterBone.TetherToken() == address(positionInfo.stableToken), dexCenter, swapRouter, phase2Info.debtSize, estimatePhase2UseCash, path);
        phase2Info.rulerAddr = msg.sender;
        phase2Info.flag = true;
        phase2Info.dexCoverReward = phase2Info.usedCash.div(100);

        if (phase2Info.dexCoverReward.add(phase2Info.usedCash) > estimatePhase2UseCash) {
            phase2Info.dexCoverReward = estimatePhase2UseCash.sub(phase2Info.usedCash);
        }

        closePosition(position);
        emit BidKatana(position, msg.sender, phase2Info.debtSize, phase2Info.usedCash, phase2Info.dexCoverReward);
    }

    function estimateAuctionPrice(
        uint256 unsettledCash,
        uint256 totalSize,
        address stakedToken,
        uint256 stakedTokenDecimals,
        uint256 stableTokenDecimals
    ) public view returns (uint256) {
        (uint256 currentPrice, uint256 decimals) = priceOracle.getLatestMixinPrice(stakedToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(decimals))).mul(102).div(100);
        uint256 overdrawnPrice = unsettledCash.mul(10**(stakedTokenDecimals.add(18).sub(stableTokenDecimals))).div(totalSize);

        if (currentPrice > overdrawnPrice) {
            return overdrawnPrice;
        }
        return currentPrice;
    }

    function executePositions(
        address[] memory closedPositions,
        address[] memory legacyPositions,
        bytes[] memory _phase1Ranks
    ) external override {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.GRAB_REWARD), "AuctionHall: Caller is not Grabber");
        if (closedPositions.length > 0) {
            require(closedPositions.length == _phase1Ranks.length, "AuctionHall: Invalid phase1Ranks");
            verifyPhase1Ranks(closedPositions, _phase1Ranks);
        }

        for (uint256 i = 0; i < legacyPositions.length; i++) {
            (, , uint256 closingBlock, ITradingHub.PositionState positionState) = tradingHub.getPositionInfo(legacyPositions[i]);
            require(positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");
            if ((block.number.sub(closingBlock) > auctionMaxBlock && !phase1Infos[legacyPositions[i]].flag && !phase2Infos[legacyPositions[i]].flag) || estimatePositionState(legacyPositions[i]) == ITradingHub.PositionState.OVERDRAWN) {
                tradingHub.updatePositionState(legacyPositions[i], ITradingHub.PositionState.OVERDRAWN);
            }
        }
    }

    function inquire()
        external
        view
        override
        returns (
            address[] memory closedPositions,
            address[] memory legacyPositions,
            bytes[] memory _phase1Ranks
        )
    {
        address[] memory closingPositions = tradingHub.getPositionsByState(ITradingHub.PositionState.CLOSING);

        uint256 posSize = closingPositions.length;
        address[] memory closedPosContainer = new address[](posSize);
        address[] memory abortedPosContainer = new address[](posSize);

        uint256 resClosedPosCount;
        uint256 resAbortedPosCount;
        for (uint256 i = 0; i < posSize; i++) {
            (, , uint256 closingBlock, ) = tradingHub.getPositionInfo(closingPositions[i]);

            if (block.number.sub(closingBlock) > phase1MaxBlock && (phase1Infos[closingPositions[i]].flag)) {
                closedPosContainer[resClosedPosCount++] = closingPositions[i];
            } else if ((block.number.sub(closingBlock) > auctionMaxBlock && !phase1Infos[closingPositions[i]].flag && !phase2Infos[closingPositions[i]].flag)) {
                abortedPosContainer[resAbortedPosCount++] = closingPositions[i];
            } else {
                ITradingHub.PositionState positionState = estimatePositionState(closingPositions[i]);
                if (positionState == ITradingHub.PositionState.OVERDRAWN) {
                    abortedPosContainer[resAbortedPosCount++] = closingPositions[i];
                } else if (positionState == ITradingHub.PositionState.CLOSED) {
                    closedPosContainer[resClosedPosCount++] = closingPositions[i];
                }
            }
        }

        closedPositions = new address[](resClosedPosCount);
        _phase1Ranks = new bytes[](resClosedPosCount);
        for (uint256 i = 0; i < resClosedPosCount; i++) {
            closedPositions[i] = closedPosContainer[i];
            _phase1Ranks[i] = bidSorted(closedPosContainer[i]);
        }

        legacyPositions = new address[](resAbortedPosCount);
        for (uint256 i = 0; i < resAbortedPosCount; i++) {
            legacyPositions[i] = abortedPosContainer[i];
        }
    }

    function estimatePositionState(address position) internal view returns (ITradingHub.PositionState positionState) {
        PositionInfo memory positionInfo = getPositionInfo(position);
        (uint256 currentPrice, uint256 tokenDecimals) = AllyLibrary.getPriceOracle(shorterBone).getLatestMixinPrice(positionInfo.stakedToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));
        uint256 overdrawnPrice = positionInfo.unsettledCash.mul(10**(uint256(positionInfo.stakedTokenDecimals).add(18).sub(uint256(positionInfo.stableTokenDecimals)))).div(positionInfo.totalSize);
        if (currentPrice > overdrawnPrice && phase1Infos[position].flag) {
            return ITradingHub.PositionState.CLOSED;
        }
        positionState = currentPrice > overdrawnPrice ? ITradingHub.PositionState.OVERDRAWN : ITradingHub.PositionState.CLOSING;
    }

    function bidSorted(address position) public view returns (bytes memory) {
        BidItem[] memory bidItems = allPhase1BidRecords[position];

        uint256 bidItemSize = bidItems.length;
        uint256[] memory _bidRanks = new uint256[](bidItemSize);

        for (uint256 i = 0; i < bidItemSize; i++) {
            _bidRanks[i] = i;
        }

        for (uint256 i = 0; i < bidItemSize; i++) {
            uint256 minItemIndex = bidItemSize.sub(i + 1);
            for (uint256 j = 0; j < bidItemSize.sub(i + 1); j++) {
                if (
                    bidItems[j].priorityFee < bidItems[minItemIndex].priorityFee ||
                    (bidItems[j].priorityFee == bidItems[minItemIndex].priorityFee && bidItems[j].bidBlock > bidItems[minItemIndex].bidBlock) ||
                    (bidItems[j].priorityFee == bidItems[minItemIndex].priorityFee && bidItems[j].bidBlock == bidItems[minItemIndex].bidBlock && bidItems[j].bidder > bidItems[minItemIndex].bidder)
                ) {
                    minItemIndex = j;
                }
            }

            if (minItemIndex != bidItemSize.sub(i + 1)) {
                BidItem memory tempItem = bidItems[minItemIndex];
                bidItems[minItemIndex] = bidItems[bidItemSize.sub(i + 1)];
                bidItems[bidItemSize.sub(i + 1)] = tempItem;

                uint256 temp = _bidRanks[minItemIndex];
                _bidRanks[minItemIndex] = _bidRanks[bidItemSize.sub(i + 1)];
                _bidRanks[bidItemSize.sub(i + 1)] = temp;
            }
        }

        return abi.encode(_bidRanks);
    }

    function verifyPhase1Ranks(address[] memory closedPositions, bytes[] memory _phase1Ranks) internal {
        for (uint256 i = 0; i < closedPositions.length; i++) {
            uint256[] memory _bidRanks = abi.decode(_phase1Ranks[i], (uint256[]));
            BidItem[] memory bidItems = allPhase1BidRecords[closedPositions[i]];
            require(_bidRanks.length == bidItems.length, "AuctionHall: Invalid bidRanks size");
            (, , uint256 closingBlock, ITradingHub.PositionState positionState) = tradingHub.getPositionInfo(closedPositions[i]);
            if (!((block.number.sub(closingBlock) > phase1MaxBlock && phase1Infos[closedPositions[i]].flag) || (estimatePositionState(closedPositions[i]) == ITradingHub.PositionState.CLOSED))) {
                continue;
            }
            require(positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");
            phase1Ranks[closedPositions[i]] = _phase1Ranks[i];
            closePosition(closedPositions[i]);

            if (_bidRanks.length <= 1) {
                break;
            }

            for (uint256 j = 0; j < _bidRanks.length.sub(1); j++) {
                uint256 m = _bidRanks[j + 1];
                uint256 n = _bidRanks[j];

                if (bidItems[m].priorityFee < bidItems[n].priorityFee) {
                    continue;
                }

                if (bidItems[m].priorityFee == bidItems[n].priorityFee && bidItems[m].bidBlock > bidItems[n].bidBlock) {
                    continue;
                }

                if (bidItems[m].priorityFee == bidItems[n].priorityFee && bidItems[m].bidBlock == bidItems[n].bidBlock && bidItems[m].bidder > bidItems[n].bidder) {
                    continue;
                }

                revert("AuctionHall: Invalid bidRanks");
            }
        }
    }

    function initialize(
        address _shorterBone,
        address _dexCenter,
        address _ipistrToken,
        address _poolGuardian,
        address _tradingHub,
        address _priceOracle,
        address _committee,
        uint256 _phase1MaxBlock,
        uint256 _auctionMaxBlock
    ) external isKeeper {
        require(!_initialized, "AuctionHall: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        dexCenter = _dexCenter;
        ipistrToken = _ipistrToken;
        poolGuardian = IPoolGuardian(_poolGuardian);
        tradingHub = ITradingHub(_tradingHub);
        priceOracle = IPriceOracle(_priceOracle);
        committee = ICommittee(_committee);
        _initialized = true;
        phase1MaxBlock = _phase1MaxBlock;
        auctionMaxBlock = _auctionMaxBlock;
    }

    function getPositionInfo(address position) internal view returns (PositionInfo memory positionInfo) {
        (, address strToken, uint256 closingBlock, ITradingHub.PositionState positionState) = tradingHub.getPositionInfo(position);
        (, address stakedToken, address stableToken, , , , , , , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, ) = IStrPool(strToken).getInfo();
        (uint256 totalSize, uint256 unsettledCash) = IStrPool(strToken).getPositionInfo(position);
        positionInfo = PositionInfo({
            strToken: strToken,
            stakedToken: stakedToken,
            stableToken: stableToken,
            stakedTokenDecimals: stakedTokenDecimals,
            stableTokenDecimals: stableTokenDecimals,
            totalSize: totalSize,
            unsettledCash: unsettledCash,
            closingBlock: closingBlock,
            positionState: positionState
        });
    }

    function closePosition(address position) internal {
        PositionInfo memory positionInfo = getPositionInfo(position);

        shorterBone.tillOut(positionInfo.stakedToken, AllyLibrary.AUCTION_HALL, positionInfo.strToken, positionInfo.totalSize);
        tradingHub.updatePositionState(position, ITradingHub.PositionState.CLOSED);
        Phase1Info storage phase1Info = phase1Infos[position];
        uint256 phase1Wonsize = phase1Info.bidSize > positionInfo.totalSize ? positionInfo.totalSize : phase1Info.bidSize;
        uint256 phase1UsedUnsettledCash = phase1Wonsize.mul(phase1Info.liquidationPrice).div(10**(positionInfo.stakedTokenDecimals.add(18).sub(positionInfo.stableTokenDecimals)));
        IStrPool(positionInfo.strToken).auctionClosed(position, phase1UsedUnsettledCash, phase2Infos[position].usedCash, 0);
    }

    function queryResidues(address position, address ruler)
        public
        view
        returns (
            uint256 stableTokenSize,
            uint256 debtTokenSize,
            uint256 priorityFee
        )
    {
        PositionInfo memory positionInfo = getPositionInfo(position);
        if (positionInfo.positionState == ITradingHub.PositionState.CLOSING) {
            return (0, 0, 0);
        }

        Phase2Info storage phase2Info = phase2Infos[position];
        Phase1Info storage phase1Info = phase1Infos[position];

        if (ruler == phase2Info.rulerAddr && !phase2Info.isWithdrawn) {
            stableTokenSize = phase2Info.dexCoverReward;
        }

        BidItem[] storage bidItems = allPhase1BidRecords[position];

        uint256[] memory bidRanks;
        if (phase1Ranks[position].length == 0) {
            bidRanks = new uint256[](bidItems.length);
            for (uint256 i = 0; i < bidItems.length; i++) {
                bidRanks[i] = i;
            }
        } else {
            bidRanks = abi.decode(phase1Ranks[position], (uint256[]));
        }

        uint256 remainingDebtSize = positionInfo.totalSize;
        for (uint256 i = 0; i < bidRanks.length; i++) {
            uint256 wonSize;

            if (!phase1Info.flag && !phase2Info.flag) {
                wonSize = 0;
            } else if (remainingDebtSize >= bidItems[bidRanks[i]].bidSize) {
                wonSize = bidItems[bidRanks[i]].bidSize;
                remainingDebtSize = remainingDebtSize.sub(wonSize);
            } else {
                wonSize = remainingDebtSize;
                remainingDebtSize = 0;
            }

            if (bidItems[bidRanks[i]].bidder == ruler && !bidItems[bidRanks[i]].takeBack) {
                if (wonSize == 0) {
                    debtTokenSize = debtTokenSize.add(bidItems[bidRanks[i]].bidSize);
                    priorityFee = priorityFee.add(bidItems[bidRanks[i]].priorityFee);
                } else {
                    debtTokenSize = debtTokenSize.add(bidItems[bidRanks[i]].bidSize).sub(wonSize);
                    uint256 stableTokenIncreased = wonSize.mul(phase1Info.liquidationPrice).div(10**(uint256(positionInfo.stakedTokenDecimals).add(18).sub(uint256(positionInfo.stableTokenDecimals))));
                    stableTokenSize = stableTokenSize.add(stableTokenIncreased);
                }
            }
        }
    }

    function retrieve(address position) external whenNotPaused {
        (uint256 stableTokenSize, uint256 debtTokenSize, uint256 priorityFee) = queryResidues(position, msg.sender);
        require(stableTokenSize.add(debtTokenSize).add(priorityFee) > 0, "AuctionHall: No asset to retrieve for now");
        _updateRulerAsset(position, msg.sender);
        (, address strToken, , ) = tradingHub.getPositionInfo(position);
        (, address stakedToken, , , , , , , , , , ) = IStrPool(strToken).getInfo();

        if (stableTokenSize > 0) {
            IStrPool(strToken).stableTillOut(msg.sender, stableTokenSize);
        }

        if (debtTokenSize > 0) {
            shorterBone.tillOut(stakedToken, AllyLibrary.AUCTION_HALL, msg.sender, debtTokenSize);
        }

        if (priorityFee > 0) {
            shorterBone.tillOut(ipistrToken, AllyLibrary.AUCTION_HALL, msg.sender, priorityFee);
        }

        emit Retrieve(position, stableTokenSize, debtTokenSize, priorityFee);
    }

    function _updateRulerAsset(address position, address ruler) internal {
        if (ruler == phase2Infos[position].rulerAddr) {
            phase2Infos[position].isWithdrawn = true;
        }

        BidItem[] storage bidItems = allPhase1BidRecords[position];

        for (uint256 i = 0; i < bidItems.length; i++) {
            if (bidItems[i].bidder == ruler) {
                bidItems[i].takeBack = true;
            }
        }
    }

    function setDexCenter(address newDexCenter) public isManager {
        dexCenter = newDexCenter;
    }
}
