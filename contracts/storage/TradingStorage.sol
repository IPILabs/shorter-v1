// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interfaces/uniswapv2/IUniswapV2Router02.sol";
import "../interfaces/IDexCenter.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/v1/model/IPoolRewardModel.sol";
import "../oracles/IPriceOracle.sol";
import "./TitanCoreStorage.sol";
import "../util/EnumerableMap.sol";

contract TradingStorage is TitanCoreStorage {
    struct PoolInfo {
        address creator;
        ISRC20 stakedToken;
        ISRC20 stableToken;
        address strToken;
        // Leverage
        uint256 leverage;
        // Optional if the pool is marked as never expires(perputual)
        uint256 durationDays;
        // Pool creation block number
        uint256 startBlock;
        // Pool expired block number
        uint256 endBlock;
        uint256 id;
        uint256 stakedTokenDecimals;
        uint256 stableTokenDecimals;
        // Listed or not
        IPoolGuardian.PoolStatus stateFlag;
    }

    struct PoolStats {
        uint256 opens;
        uint256 legacies;
        uint256 closings;
        uint256 ends;
    }

    struct PositionCube {
        address addr;
        uint64 poolId;
    }

    struct PositionBlock {
        uint256 openBlock;
        uint256 closingBlock;
        uint256 overdrawnBlock;
        uint256 closedBlock;
        uint256 lastSellBlock;
    }

    struct PositionIndex {
        uint64 poolId;
        address strToken;
        uint256 positionState;
    }

    bool internal _initialized;
    uint256 public allPositionSize;
    IDexCenter public dexCenter;
    IPoolGuardian public poolGuardian;
    IPriceOracle public priceOracle;

    mapping(uint256 => mapping(address => uint256)) userReentrantLocks;

    mapping(uint256 => PoolStats) public poolStatsMap;

    mapping(uint256 => address) public allPositions;
    mapping(address => mapping(uint256 => PositionCube)) public userPositions;
    mapping(address => uint256) public userPositionSize;

    mapping(uint256 => mapping(uint256 => address)) public poolPositions;
    mapping(uint256 => uint256) public poolPositionSize;

    mapping(address => PositionIndex) public positionInfoMap;
    mapping(address => PositionBlock) public positionBlocks;
}
