// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/Path.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/v1/IAuctionHall.sol";
import "../interfaces/IDexCenter.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IWETH.sol";
import "../criteria/ChainSchema.sol";
import "../storage/ThemisStorage.sol";
import "../util/BoringMath.sol";

contract AuctionHallImpl is ChainSchema, ThemisStorage, IAuctionHall {
    using BoringMath for uint256;
    using SafeToken for ISRC20;
    using Path for bytes;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    modifier reentrantLock(uint256 code) {
        require(userReentrantLocks[code][msg.sender] == 0, "TradingHub: Reentrant call");
        userReentrantLocks[code][msg.sender] = 1;
        _;
        userReentrantLocks[code][msg.sender] = 0;
    }

    modifier onlyRuler() {
        require(committee.isRuler(msg.sender), "AuctionHall: Caller is not a ruler");
        _;
    }

    function bidTanto(
        address position,
        uint256 bidSize,
        uint256 priorityFee
    ) external payable whenNotPaused onlyRuler reentrantLock(1000) {
        (, address stakedToken, , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, uint256 totalSize, uint256 unsettledCash, uint256 closingBlock, ITradingHub.PositionState positionState) = _getPositionInfo(position);

        require(bidSize > 0 && bidSize <= totalSize, "AuctionHall: Invalid bidSize");
        require(positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");
        require(block.number.sub(closingBlock) <= phase1MaxBlock, "AuctionHall: Tanto is over");
        require(allPhase1BidRecords[position].length < 512, "AuctionHall: Too many bids");

        Phase1Info storage phase1Info = phase1Infos[position];
        require(!phase1Info.flag, "AuctionHall: Tanto is over");
        phase1Info.bidSize = phase1Info.bidSize.add(bidSize);
        phase1Info.liquidationPrice = estimateAuctionPrice(unsettledCash, totalSize, stakedToken, stakedTokenDecimals, stableTokenDecimals);

        if (stakedToken == poolGuardian.WrappedEtherAddr()) {
            require(bidSize == msg.value, "AuctionHall: Invalid amount");
            IWETH(stakedToken).deposit{value: msg.value}();
        } else {
            shorterBone.tillIn(stakedToken, msg.sender, AllyLibrary.AUCTION_HALL, bidSize);
        }

        shorterBone.tillIn(ipistrToken, msg.sender, AllyLibrary.AUCTION_HALL, priorityFee);

        if (phase1Info.bidSize >= totalSize) {
            phase1Info.flag = true;
        }

        allPhase1BidRecords[position].push(BidItem({takeBack: false, bidBlock: block.number.to64(), bidder: msg.sender, bidSize: bidSize, priorityFee: priorityFee}));

        emit BidTanto(position, msg.sender, bidSize, priorityFee);
    }

    function bidKatana(address position, bytes memory path) external whenNotPaused onlyRuler reentrantLock(1001) {
        (, , , ITradingHub.PositionState positionState) = tradingHub.getPositionInfo(position);
        require(positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");

        Phase2Info storage phase2Info = phase2Infos[position];
        (uint256 _debtSize, uint256 estimatePhase2UseCash) = _getPhase1ResidualDebt(position);
        phase2Info.debtSize = _debtSize;
        phase2Info.usedCash = _dexCover(position, phase2Info.debtSize, estimatePhase2UseCash, path);
        phase2Info.rulerAddr = msg.sender;
        phase2Info.flag = true;
        phase2Info.dexCoverReward = phase2Info.usedCash.div(100);

        if (phase2Info.dexCoverReward.add(phase2Info.usedCash) > estimatePhase2UseCash) {
            phase2Info.dexCoverReward = estimatePhase2UseCash.sub(phase2Info.usedCash);
        }

        _closePosition(position);
        emit BidKatana(position, msg.sender, phase2Info.debtSize, phase2Info.usedCash, phase2Info.dexCoverReward);
    }

    function _dexCover(
        address _position,
        uint256 _amountOut,
        uint256 _amountInMax,
        bytes memory path
    ) internal returns (uint256 amountIn) {
        (address strToken, address stakedToken, address stableToken, , , , , , ) = _getPositionInfo(_position);
        (, address swapRouter, ) = shorterBone.getTokenInfo(stakedToken);
        IDexCenter(dexCenter).checkPath(stakedToken, stableToken, swapRouter, path);
        amountIn = IPool(strToken).dexCover(IDexCenter(dexCenter).isSwapRouterV3(swapRouter), shorterBone.TetherToken() == stableToken, dexCenter, swapRouter, _amountOut, _amountInMax, path);
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
        uint256 legacyPositionCount = legacyPositions.length;
        require(closedPositions.length + legacyPositionCount < 512, "AcutionHall: Tasks too heavy");
        if (closedPositions.length > 0) {
            require(closedPositions.length == _phase1Ranks.length, "AuctionHall: Invalid phase1Ranks");
            verifyPhase1Ranks(closedPositions, _phase1Ranks);
        }

        for (uint256 i = 0; i < legacyPositionCount; i++) {
            (, , uint256 closingBlock, ITradingHub.PositionState positionState) = tradingHub.getPositionInfo(legacyPositions[i]);
            require(positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");
            if ((block.number.sub(closingBlock) > auctionMaxBlock && !phase1Infos[legacyPositions[i]].flag && !phase2Infos[legacyPositions[i]].flag) || _estimatePositionState(legacyPositions[i]) == ITradingHub.PositionState.OVERDRAWN) {
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
                ITradingHub.PositionState positionState = _estimatePositionState(closingPositions[i]);
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

    function _estimatePositionState(address position) internal view returns (ITradingHub.PositionState positionState) {
        (, address stakedToken, , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, uint256 totalSize, uint256 unsettledCash, , ) = _getPositionInfo(position);

        (uint256 currentPrice, uint256 tokenDecimals) = AllyLibrary.getPriceOracle(shorterBone).getLatestMixinPrice(stakedToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(tokenDecimals)));
        uint256 overdrawnPrice = unsettledCash.mul(10**(stakedTokenDecimals.add(18).sub(stableTokenDecimals))).div(totalSize);
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
            if (!((block.number.sub(closingBlock) > phase1MaxBlock && phase1Infos[closedPositions[i]].flag) || (_estimatePositionState(closedPositions[i]) == ITradingHub.PositionState.CLOSED))) {
                continue;
            }
            require(positionState == ITradingHub.PositionState.CLOSING, "AuctionHall: Not a closing position");
            phase1Ranks[closedPositions[i]] = _phase1Ranks[i];
            _closePosition(closedPositions[i]);

            if (_bidRanks.length <= 1) {
                break;
            }
            uint256 bidRankLoops = _bidRanks.length.sub(1);

            for (uint256 j = 0; j < bidRankLoops; j++) {
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
    ) external isSavior {
        require(_dexCenter != address(0), "AuctionHall: DexCenter is zero address");
        require(_ipistrToken != address(0), "AuctionHall: IpistrToken is zero address");
        shorterBone = IShorterBone(_shorterBone);
        dexCenter = _dexCenter;
        ipistrToken = _ipistrToken;
        poolGuardian = IPoolGuardian(_poolGuardian);
        tradingHub = ITradingHub(_tradingHub);
        priceOracle = IPriceOracle(_priceOracle);
        committee = ICommittee(_committee);
        phase1MaxBlock = _phase1MaxBlock;
        auctionMaxBlock = _auctionMaxBlock;
    }

    function _getPositionInfo(address position)
        internal
        view
        returns (
            address strPool,
            address stakedToken,
            address stableToken,
            uint256 stakedTokenDecimals,
            uint256 stableTokenDecimals,
            uint256 totalSize,
            uint256 unsettledCash,
            uint256 closingBlock,
            ITradingHub.PositionState positionState
        )
    {
        (, strPool, closingBlock, positionState) = tradingHub.getPositionInfo(position);
        (, stakedToken, stableToken, , , , , , , stakedTokenDecimals, stableTokenDecimals, ) = IPool(strPool).getInfo();
        (totalSize, unsettledCash) = IPool(strPool).getPositionInfo(position);
    }

    function _closePosition(address position) internal {
        (address strToken, address stakedToken, , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, uint256 totalSize, , , ) = _getPositionInfo(position);

        shorterBone.tillOut(stakedToken, AllyLibrary.AUCTION_HALL, strToken, totalSize);
        tradingHub.updatePositionState(position, ITradingHub.PositionState.CLOSED);
        Phase1Info storage phase1Info = phase1Infos[position];
        uint256 phase1WonSize = phase1Info.bidSize > totalSize ? totalSize : phase1Info.bidSize;
        uint256 phase1UsedUnsettledCash = phase1WonSize.mul(phase1Info.liquidationPrice).div(10**(stakedTokenDecimals.add(18).sub(stableTokenDecimals)));
        IPool(strToken).auctionClosed(position, phase1UsedUnsettledCash, phase2Infos[position].usedCash, 0);
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
        (, , , , , uint256 totalSize, , , ITradingHub.PositionState positionState) = _getPositionInfo(position);

        if (positionState == ITradingHub.PositionState.CLOSING) {
            return (0, 0, 0);
        }

        uint256 remainingDebtSize = totalSize;
        Phase2Info storage phase2Info = phase2Infos[position];
        if (phase2Info.flag) {
            if (ruler == phase2Info.rulerAddr && !phase2Info.isWithdrawn) {
                stableTokenSize = phase2Info.dexCoverReward;
            }
            remainingDebtSize = remainingDebtSize.sub(phase2Info.debtSize);
        }

        (stableTokenSize, debtTokenSize, priorityFee) = _getPhase1Residues(ruler, position, remainingDebtSize, stableTokenSize, phase2Info.flag);
    }

    function retrieve(address position) external whenNotPaused reentrantLock(1002) {
        (uint256 stableTokenSize, uint256 debtTokenSize, uint256 priorityFee) = queryResidues(position, msg.sender);
        require(stableTokenSize.add(debtTokenSize).add(priorityFee) > 0, "AuctionHall: No asset to retrieve for now");
        _updateRulerAsset(position, msg.sender);
        (, address strToken, , ) = tradingHub.getPositionInfo(position);
        (, address stakedToken, , , , , , , , , , ) = IPool(strToken).getInfo();

        if (stableTokenSize > 0) {
            IPool(strToken).stableTillOut(msg.sender, stableTokenSize);
        }

        if (debtTokenSize > 0) {
            if (stakedToken == poolGuardian.WrappedEtherAddr()) {
                IWETH(stakedToken).withdraw(debtTokenSize);
                msg.sender.transfer(debtTokenSize);
            } else {
                shorterBone.tillOut(stakedToken, AllyLibrary.AUCTION_HALL, msg.sender, debtTokenSize);
            }
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

    function _getPhase1Residues(
        address _ruler,
        address _position,
        uint256 _remainingDebtSize,
        uint256 _stableTokenSize,
        bool _phase2Flag
    )
        internal
        view
        returns (
            uint256 stableTokenSize,
            uint256 debtTokenSize,
            uint256 priorityFee
        )
    {
        BidItem[] storage bidItems = allPhase1BidRecords[_position];
        uint256[] memory bidRanks;
        if (phase1Ranks[_position].length == 0) {
            bidRanks = new uint256[](bidItems.length);
            for (uint256 i = 0; i < bidItems.length; i++) {
                bidRanks[i] = i;
            }
        } else {
            bidRanks = abi.decode(phase1Ranks[_position], (uint256[]));
        }
        Phase1Info storage phase1Info = phase1Infos[_position];
        (, , , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, , , , ) = _getPositionInfo(_position);
        uint256 phase1BidCount = bidRanks.length;
        for (uint256 i = 0; i < phase1BidCount; i++) {
            stableTokenSize = stableTokenSize.add(_stableTokenSize);
            uint256 wonSize;
            if (!phase1Info.flag && !_phase2Flag) {
                wonSize = 0;
            } else if (_remainingDebtSize >= bidItems[bidRanks[i]].bidSize) {
                wonSize = bidItems[bidRanks[i]].bidSize;
                _remainingDebtSize = _remainingDebtSize.sub(wonSize);
            } else {
                wonSize = _remainingDebtSize;
                _remainingDebtSize = 0;
            }
            if (bidItems[bidRanks[i]].bidder == _ruler && !bidItems[bidRanks[i]].takeBack) {
                if (wonSize == 0) {
                    debtTokenSize = debtTokenSize.add(bidItems[bidRanks[i]].bidSize);
                    priorityFee = priorityFee.add(bidItems[bidRanks[i]].priorityFee);
                } else {
                    debtTokenSize = debtTokenSize.add(bidItems[bidRanks[i]].bidSize).sub(wonSize);
                    uint256 stableTokenIncreased = wonSize.mul(phase1Info.liquidationPrice).div(10**(stakedTokenDecimals.add(18).sub(stableTokenDecimals)));
                    stableTokenSize = stableTokenSize.add(stableTokenIncreased);
                }
            }
        }
    }

    function _getPhase1ResidualDebt(address _position) internal view returns (uint256 debtSize, uint256 estimatePhase2UseCash) {
        Phase1Info storage phase1Info = phase1Infos[_position];
        require(!phase1Info.flag, "AuctionHall: Position closed");
        (, , , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, uint256 totalSize, uint256 unsettledCash, uint256 closingBlock, ) = _getPositionInfo(_position);
        require(block.number.sub(closingBlock) > phase1MaxBlock && block.number.sub(closingBlock) <= auctionMaxBlock, "AuctionHall: Katana is over");
        uint256 decimalDiff = 10**(stakedTokenDecimals.add(18).sub(stableTokenDecimals));
        uint256 phase1UsedUnsettledCash = phase1Info.bidSize.mul(phase1Info.liquidationPrice).div(decimalDiff);
        debtSize = totalSize.sub(phase1Info.bidSize);
        estimatePhase2UseCash = unsettledCash.sub(phase1UsedUnsettledCash);
    }
}
