// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/Path.sol";
import "../libraries/AllyLibrary.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/v1/IAuctionHall.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IDexCenter.sol";
import "../criteria/ChainSchema.sol";
import "../storage/AresStorage.sol";
import "../util/BoringMath.sol";

/// @notice Hub for dealing with orders, positions and traders
contract TradingHubImpl is ChainSchema, AresStorage, ITradingHub {
    using BoringMath for uint256;
    using Path for bytes;
    using AllyLibrary for IShorterBone;

    uint256 internal constant OPEN_STATE = 1;
    uint256 internal constant CLOSING_STATE = 2;
    uint256 internal constant OVERDRAWN_STATE = 4;
    uint256 internal constant CLOSED_STATE = 8;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    modifier reentrantLock(uint256 code) {
        require(userReentrantLocks[code][msg.sender] == 0, "TradingHub: Reentrant call");
        userReentrantLocks[code][msg.sender] = 1;
        _;
        userReentrantLocks[code][msg.sender] = 0;
    }

    modifier onlySwapRouter(address _swapRouter) {
        require(dexCenter.entitledSwapRouters(_swapRouter), "TradingHub: Invalid SwapRouter");
        _;
    }

    modifier onlyCommittee() {
        shorterBone.assertCaller(msg.sender, AllyLibrary.COMMITTEE);
        _;
    }

    function sellShort(
        uint256 poolId,
        uint256 amount,
        uint256 amountOutMin,
        bytes memory path
    ) external whenNotPaused reentrantLock(0) {
        PoolInfo memory pool = _getPoolInfo(poolId);
        (, address swapRouter, ) = shorterBone.getTokenInfo(address(pool.stakedToken));

        require(dexCenter.entitledSwapRouters(swapRouter), "TradingHub sellShort: Invalid SwapRouter");
        require(path.getTokenIn() == address(pool.stakedToken) && path.getTokenOut() == address(pool.stableToken), "TradingHub: Invalid path");
        require(pool.stateFlag == IPoolGuardian.PoolStatus.RUNNING && pool.endBlock > block.number, "TradingHub: Expired pool");

        uint256 estimatePrice = priceOracle.getLatestMixinPrice(address(pool.stakedToken));
        require(estimatePrice.mul(amount).mul(pool.leverage.mul(100).sub(30)).div(pool.leverage.mul(100)) < amountOutMin.mul(10**(uint256(18).add(pool.stakedTokenDecimals).sub(pool.stableTokenDecimals))), "TradingHub: Slippage too large");
        address position = _duplicatedOpenPosition(poolId, msg.sender);
        if (position == address(0)) {
            position = address(uint160(uint256(keccak256(abi.encode(poolId, msg.sender, block.number)))));
            userPositions[msg.sender][userPositionSize[msg.sender]++] = PositionCube({addr: position, poolId: poolId.to64()});
            poolPositions[poolId][poolPositionSize[poolId]++] = position;
            allPositions[allPositionSize++] = position;
            positionInfoMap[position] = PositionIndex({poolId: poolId.to64(), strToken: pool.strToken, positionState: OPEN_STATE});
            poolStatsMap[poolId].opens++;
            positionBlocks[position].openBlock = block.number;
            emit PositionOpened(poolId, msg.sender, position, amount);
        } else {
            emit PositionIncreased(poolId, msg.sender, position, amount);
        }
        IPool(pool.strToken).borrow(dexCenter.isSwapRouterV3(swapRouter), address(dexCenter), swapRouter, position, msg.sender, amount, amountOutMin, path);
        positionBlocks[position].lastSellBlock = block.number;
    }

    function buyCover(
        uint256 poolId,
        uint256 amount,
        uint256 amountInMax,
        bytes memory path
    ) external whenNotPaused reentrantLock(1) {
        PoolInfo memory pool = _getPoolInfo(poolId);
        (, address swapRouter, ) = shorterBone.getTokenInfo(address(pool.stakedToken));
        require(dexCenter.entitledSwapRouters(swapRouter), "TradingHub buyCover: Invalid SwapRouter");
        dexCenter.checkPath(address(pool.stakedToken), address(pool.stableToken), swapRouter, path);

        address position = _duplicatedOpenPosition(poolId, msg.sender);
        require(position != address(0), "TradingHub: Position not found");
        require(positionBlocks[position].lastSellBlock < block.number, "TradingHub: Illegit buyCover");

        bool isClosed = IPool(pool.strToken).repay(dexCenter.isSwapRouterV3(swapRouter), shorterBone.TetherToken() == address(pool.stableToken), address(dexCenter), swapRouter, position, msg.sender, amount, amountInMax, path);

        if (isClosed) {
            _updatePositionState(position, CLOSED_STATE);
        }

        emit PositionDecreased(poolId, msg.sender, position, amount);
    }

    function getPositionState(address position)
        external
        view
        override
        returns (
            uint256,
            address,
            uint256,
            uint256
        )
    {
        PositionIndex storage positionInfo = positionInfoMap[position];
        return (uint256(positionInfo.poolId), positionInfo.strToken, uint256(positionBlocks[position].closingBlock), positionInfo.positionState);
    }

    function getBatchPositionState(address[] calldata positions) external view override returns (uint256[] memory positionsState) {
        uint256 positionSize = positions.length;
        positionsState = new uint256[](positionSize);
        for (uint256 i = 0; i < positionSize; i++) {
            positionsState[i] = positionInfoMap[positions[i]].positionState;
        }
    }

    function getPositions(address account) external view returns (address[] memory positions) {
        positions = new address[](userPositionSize[account]);
        for (uint256 i = 0; i < userPositionSize[account]; i++) {
            positions[i] = userPositions[account][i].addr;
        }
    }

    function initialize(
        address _shorterBone,
        address _poolGuardian,
        address _dexCenter,
        address _priceOracle
    ) external isSavior {
        require(!_initialized, "TradingHub: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
        dexCenter = IDexCenter(_dexCenter);
        priceOracle = IPriceOracle(_priceOracle);
        _initialized = true;
    }

    function _getPoolInfo(uint256 poolId) internal view returns (PoolInfo memory poolInfo) {
        (, address strToken, ) = poolGuardian.getPoolInfo(poolId);
        (address creator, address stakedToken, address stableToken, , uint256 leverage, uint256 durationDays, uint256 startBlock, uint256 endBlock, uint256 id, uint256 stakedTokenDecimals, uint256 stableTokenDecimals, IPoolGuardian.PoolStatus stateFlag) = IPool(strToken).getMetaInfo();
        poolInfo = PoolInfo({
            creator: creator,
            stakedToken: ISRC20(stakedToken),
            stableToken: ISRC20(stableToken),
            strToken: strToken,
            leverage: leverage,
            durationDays: durationDays,
            startBlock: startBlock,
            endBlock: endBlock,
            id: id,
            stakedTokenDecimals: stakedTokenDecimals,
            stableTokenDecimals: stableTokenDecimals,
            stateFlag: stateFlag
        });
    }

    function isPoolWithdrawable(uint256 poolId) external view override returns (bool) {
        return poolStatsMap[poolId].overdrawns == 0;
    }

    function setBatchClosePositions(ITradingHub.BatchPositionInfo[] calldata batchPositionInfos) external override {
        shorterBone.assertCaller(msg.sender, AllyLibrary.GRAB_REWARD);
        uint256 positionCount = batchPositionInfos.length;
        for (uint256 i = 0; i < positionCount; i++) {
            (, address strPool, IPoolGuardian.PoolStatus poolStatus) = poolGuardian.getPoolInfo(batchPositionInfos[i].poolId);
            require(poolStatus == IPoolGuardian.PoolStatus.RUNNING, "TradingHub: Pool is not running");
            (, , , , , , , uint256 endBlock, , , , ) = IPool(strPool).getMetaInfo();
            require(block.number > endBlock, "TradingHub: Pool is not Liquidating");
            if (batchPositionInfos[i].positions.length > 0) {
                IPool(strPool).batchUpdateFundingFee(batchPositionInfos[i].positions);
            }
            for (uint256 j = 0; j < batchPositionInfos[i].positions.length; j++) {
                PositionIndex storage positionInfo = positionInfoMap[batchPositionInfos[i].positions[j]];
                require(positionInfo.positionState == OPEN_STATE, "TradingHub: Position is not open");
                _updatePositionState(batchPositionInfos[i].positions[j], CLOSING_STATE);
            }
            if (poolStatsMap[batchPositionInfos[i].poolId].opens > 0) break;
            if (poolStatsMap[batchPositionInfos[i].poolId].closings > 0 || poolStatsMap[batchPositionInfos[i].poolId].overdrawns > 0) {
                poolGuardian.setStateFlag(batchPositionInfos[i].poolId, IPoolGuardian.PoolStatus.LIQUIDATING);
            } else {
                poolGuardian.setStateFlag(batchPositionInfos[i].poolId, IPoolGuardian.PoolStatus.ENDED);
            }
        }
    }

    function updatePositionState(address position, uint256 positionState) external override {
        require(shorterBone.checkCaller(msg.sender, AllyLibrary.AUCTION_HALL) || shorterBone.checkCaller(msg.sender, AllyLibrary.VAULT_BUTLER), "TradingHub: Caller is neither AuctionHall nor VaultButler");
        _updatePositionState(position, positionState);
    }

    function batchUpdatePositionState(address[] calldata positions, uint256[] calldata positionsState) external override {
        require(shorterBone.checkCaller(msg.sender, AllyLibrary.AUCTION_HALL), "TradingHub: Caller is not AuctionHall");
        uint256 positionCount = positions.length;
        for (uint256 i = 0; i < positionCount; i++) {
            if (positionsState[i] > 0) {
                _updatePositionState(positions[i], positionsState[i]);
            }
        }
    }

    function _duplicatedOpenPosition(uint256 poolId, address user) internal view returns (address position) {
        for (uint256 i = 0; i < userPositionSize[user]; i++) {
            PositionCube storage positionCube = userPositions[user][i];
            if (positionCube.poolId == poolId && positionInfoMap[positionCube.addr].positionState == OPEN_STATE) {
                return positionCube.addr;
            }
        }
    }

    function _updatePositionState(address position, uint256 positionState) internal {
        PositionIndex storage positionIndex = positionInfoMap[position];
        PoolStats storage poolStats = poolStatsMap[uint256(positionIndex.poolId)];
        if (positionIndex.positionState == OPEN_STATE) {
            poolStats.opens--;
        } else if (positionIndex.positionState == CLOSING_STATE) {
            poolStats.closings--;
        } else if (positionIndex.positionState == OVERDRAWN_STATE) {
            poolStats.overdrawns--;
        }

        if (positionState == CLOSING_STATE) {
            poolStats.closings++;
            positionBlocks[position].closingBlock = block.number;
            IAuctionHall(shorterBone.getAuctionHall()).initAuctionPosition(position, positionInfoMap[position].strToken, block.number);
            emit PositionClosing(position);
        } else if (positionState == OVERDRAWN_STATE) {
            poolStats.overdrawns++;
            positionBlocks[position].overdrawnBlock = block.number;
            emit PositionOverdrawn(position);
        } else if (positionState == CLOSED_STATE) {
            poolStats.ends++;
            positionBlocks[position].closedBlock = block.number;
            emit PositionClosed(position);
        }

        positionInfoMap[position].positionState = positionState;
    }

    function getPositionsByAccount(address account, uint256 positionState) external view returns (address[] memory) {
        uint256 poolPosSize = userPositionSize[account];
        address[] memory posContainer = new address[](poolPosSize);

        uint256 resPosCount;
        for (uint256 i = 0; i < poolPosSize; i++) {
            if (positionInfoMap[userPositions[account][i].addr].positionState == positionState) {
                posContainer[resPosCount++] = userPositions[account][i].addr;
            }
        }

        address[] memory resPositions = new address[](resPosCount);
        for (uint256 i = 0; i < resPosCount; i++) {
            resPositions[i] = posContainer[i];
        }

        return resPositions;
    }

    function getPositionsByPoolId(uint256 poolId, uint256 positionState) external view override returns (address[] memory) {
        uint256 poolPosSize = poolPositionSize[poolId];
        address[] memory posContainer = new address[](poolPosSize);

        uint256 resPosCount;
        for (uint256 i = 0; i < poolPosSize; i++) {
            if (positionInfoMap[poolPositions[poolId][i]].positionState == positionState) {
                posContainer[resPosCount++] = poolPositions[poolId][i];
            }
        }

        address[] memory resPositions = new address[](resPosCount);
        for (uint256 i = 0; i < resPosCount; i++) {
            resPositions[i] = posContainer[i];
        }

        return resPositions;
    }

    function getPositionsByState(uint256 positionState) external view override returns (address[] memory) {
        address[] memory posContainer = new address[](allPositionSize);

        uint256 resPosCount;
        for (uint256 i = 0; i < allPositionSize; i++) {
            if (positionInfoMap[allPositions[i]].positionState == positionState) {
                posContainer[resPosCount++] = allPositions[i];
            }
        }

        address[] memory resPositions = new address[](resPosCount);
        for (uint256 i = 0; i < resPosCount; i++) {
            resPositions[i] = posContainer[i];
        }

        return resPositions;
    }

    function setDexCenter(address newDexCenter) external onlyCommittee {
        require(newDexCenter != address(0), "TradingHub: NewDexCenter is zero address");
        dexCenter = IDexCenter(newDexCenter);
    }

    function setPriceOracle(address newPriceOracle) external onlyCommittee {
        require(newPriceOracle != address(0), "TradingHub: NewPriceOracle is zero address");
        priceOracle = IPriceOracle(newPriceOracle);
    }
}
