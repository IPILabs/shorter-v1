// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./TitanCoreStorage.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/IPool.sol";
import "../interfaces/v1/IWrapRouter.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/v1/model/IPoolRewardModel.sol";

contract PoolStorage is TitanCoreStorage {
    uint256 internal id;
    address internal creator;
    uint8 internal stakedTokenDecimals;
    uint8 internal stableTokenDecimals;
    // Staked single token contract
    ISRC20 internal stakedToken;
    ISRC20 internal stableToken;
    // Allowed max leverage
    uint64 internal leverage;
    // Optional if the pool is marked as never expires(perputual)
    uint64 internal durationDays;
    // Pool creation block number
    uint64 internal startBlock;
    // Pool expired block number
    uint64 internal endBlock;

    uint256 public currentRound;
    uint256 public totalTradingFee;
    uint256 internal totalBorrowAmount;

    ISRC20 public wrappedToken;
    IWrapRouter public wrapRouter;
    // Determining whether or not this pool is listed and present
    IPoolGuardian.PoolStatus internal stateFlag;

    bool public isLegacyLeftover;
    address public tradingHub;
    IPoolRewardModel public poolRewardModel;
    IPoolGuardian public poolGuardian;
    address public WrappedEtherAddr;

    struct PositionInfo {
        address trader;
        bool closedFlag;
        uint64 lastestFeeBlock;
        uint256 totalSize;
        uint256 unsettledCash;
        uint256 remnantAsset;
        uint256 totalFee;
    }
    mapping(uint256 => mapping(address => uint256)) userReentrantLocks;

    mapping(address => uint256) public userStakedTokenAmount;

    mapping(address => uint256) public userWrappedTokenAmount;

    mapping(address => uint256) public tradingFeeOf;

    mapping(address => uint256) public currentRoundTradingFeeOf;

    mapping(address => uint256) public tradingVolumeOf;

    mapping(address => PositionInfo) public positionInfoMap;

    mapping(address => uint64) public poolUserUpdateBlock;

    /// @notice Emitted when a new pool is created
    event PoolActivated(uint256 indexed poolId);
    /// @notice Emitted when user deposit tokens into a pool
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    /// @notice Emitted when user harvest from a pool
    event Harvest(address indexed user, uint256 indexed poolId, uint256 pending);
    /// @notice Emitted when user withdraw from a pool
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount);
    /// @notice Emitted when user borrow tokens from a pool
    event Borrow(address indexed user, uint256 indexed poolId, uint256 amount);
    /// @notice Emitted when user repay fund to a pool
    event Repay(address indexed user, uint256 indexed poolId, uint256 amount);
}
