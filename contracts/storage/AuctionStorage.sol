// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../interfaces/IShorterBone.sol";
import "../interfaces/v1/IAuctionHall.sol";
import "../interfaces/v1/IVaultButler.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/governance/ICommittee.sol";
import "../oracles/IPriceOracle.sol";
import "../interfaces/uniswapv2/IUniswapV2Router02.sol";
import "./TitanCoreStorage.sol";

contract AuctionStorage is TitanCoreStorage {
    struct Phase1Info {
        uint256 bidSize;
        uint256 liquidationPrice;
        bool isSorted;
        bool flag;
    }

    struct Phase2Info {
        bool flag;
        bool isWithdrawn;
        address rulerAddr;
        uint256 debtSize;
        uint256 usedCash;
        uint256 dexCoverReward;
    }

    struct BidItem {
        bool takeBack;
        uint64 bidBlock;
        address bidder;
        uint256 bidSize;
        uint256 priorityFee;
    }

    struct AuctionPositonInfo {
        address strPool;
        address stakedToken;
        address stableToken;
        uint256 closingBlock;
        uint256 totalSize;
        uint256 unsettledCash;
        uint256 stakedTokenDecimals;
        uint256 stableTokenDecimals;
    }

    uint256 public phase1MaxBlock;
    uint256 public auctionMaxBlock;
    address public dexCenter;
    address public ipistrToken;
    address public WrappedEtherAddr;
    ICommittee public committee;
    IPoolGuardian public poolGuardian;
    ITradingHub public tradingHub;
    IPriceOracle public priceOracle;

    mapping(uint256 => mapping(address => uint256)) userReentrantLocks;
    mapping(address => mapping(address => uint256)) public userBidTimes;
    mapping(address => mapping(address => uint256)) public userLastBidBlock;

    mapping(address => Phase1Info) public phase1Infos;
    mapping(address => Phase2Info) public phase2Infos;

    /// @notice { Position => BidItem[] } During Phase 1
    mapping(address => BidItem[]) public allPhase1BidRecords;
    mapping(address => AuctionPositonInfo) public auctionPositonInfoMap;
}
