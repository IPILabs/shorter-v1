// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/Path.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IDexCenter.sol";
import "../criteria/ChainSchema.sol";
import "../storage/AresStorage.sol";
import "../util/BoringMath.sol";

/// @notice Hub for dealing with orders, positions and traders
contract TradingHubImpl is ChainSchema, AresStorage, ITradingHub {
    using BoringMath for uint256;
    using Path for bytes;

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

    modifier onlyGrabber() {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.GRAB_REWARD), "TradingHub: Caller is not Grabber");
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

        uint256 estimatePrice = priceOracle.getTokenPrice(address(pool.stakedToken));
        require(estimatePrice.mul(amount).mul(9) < amountOutMin.mul(10**(uint256(19).add(pool.stakedTokenDecimals).sub(pool.stableTokenDecimals))), "TradingHub: Slippage too large");
        address position = _duplicatedOpenPosition(poolId, msg.sender);
        if (position == address(0)) {
            position = address(uint160(uint256(keccak256(abi.encode(poolId, msg.sender, block.number)))));
            userPositions[msg.sender][userPositionSize[msg.sender]++] = PositionCube({addr: position, poolId: poolId.to64()});
            poolPositions[poolId][poolPositionSize[poolId]++] = position;
            allPositions[allPositionSize++] = position;
            positionInfoMap[position] = PositionInfo({poolId: poolId.to64(), strToken: pool.strToken, positionState: PositionState.OPEN});
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
            _updatePositionState(position, PositionState.CLOSED);
        }

        emit PositionDecreased(poolId, msg.sender, position, amount);
    }

    function getPositionInfo(address position)
        external
        view
        override
        returns (
            uint256,
            address,
            uint256,
            PositionState
        )
    {
        PositionInfo storage positionInfo = positionInfoMap[position];
        return (uint256(positionInfo.poolId), positionInfo.strToken, uint256(positionBlocks[position].closingBlock), positionInfo.positionState);
    }

    function getPositions(address account) external view returns (address[] memory positions) {
        positions = new address[](userPositionSize[account]);
        for (uint256 i = 0; i < userPositionSize[account]; i++) {
            positions[i] = userPositions[account][i].addr;
        }
    }

    function initialize(address _shorterBone, address _poolGuardian) external isSavior {
        require(!_initialized, "TradingHub: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
        _initialized = true;
    }

    function _getPoolInfo(uint256 poolId) internal view returns (PoolInfo memory poolInfo) {
        (, address strToken, ) = poolGuardian.getPoolInfo(poolId);
        (address creator, address stakedToken, address stableToken, , uint256 leverage, uint256 durationDays, uint256 startBlock, uint256 endBlock, uint256 id, uint256 stakedTokenDecimals, uint256 stableTokenDecimals, IPoolGuardian.PoolStatus stateFlag) = IPool(strToken).getInfo();
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

    function executePositions(address[] memory positions) external override onlyGrabber {
        uint256 positionCount = positions.length;
        for (uint256 i = 0; i < positionCount; i++) {
            PositionInfo storage positionInfo = positionInfoMap[positions[i]];
            require(positionInfo.positionState == PositionState.OPEN, "TradingHub: Not a open position");

            PositionState positionState = IPool(positionInfo.strToken).updatePositionToAuctionHall(positions[i]);
            if (positionState == PositionState.CLOSING || positionState == PositionState.OVERDRAWN) {
                _updatePositionState(positions[i], positionState);
            }
        }
    }

    function isPoolWithdrawable(uint256 poolId) external view override returns (bool) {
        uint256 poolPosSize = poolPositionSize[poolId];
        for (uint256 i = 0; i < poolPosSize; i++) {
            if (positionInfoMap[poolPositions[poolId][i]].positionState == PositionState.OVERDRAWN) {
                return false;
            }
        }

        return true;
    }

    function setBatchClosePositions(ITradingHub.BatchPositionInfo[] memory batchPositionInfos) external override onlyGrabber {
        uint256 positionCount = batchPositionInfos.length;
        for (uint256 i = 0; i < positionCount; i++) {
            (, address strPool, IPoolGuardian.PoolStatus poolStatus) = poolGuardian.getPoolInfo(batchPositionInfos[i].poolId);
            require(poolStatus == IPoolGuardian.PoolStatus.RUNNING, "TradingHub: Pool is not running");
            (, , , , , , , uint256 endBlock, , , , ) = IPool(strPool).getInfo();
            require(block.number > endBlock, "TradingHub: Pool is not Liquidating");
            for (uint256 j = 0; j < batchPositionInfos[i].positions.length; j++) {
                PositionInfo storage positionInfo = positionInfoMap[batchPositionInfos[i].positions[j]];
                require(positionInfo.positionState == PositionState.OPEN, "TradingHub: Position is not open");
                _updatePositionState(batchPositionInfos[i].positions[j], PositionState.CLOSING);
            }
            if (batchPositionInfos[i].positions.length > 0) {
                IPool(strPool).batchUpdateFundingFee(batchPositionInfos[i].positions);
            }
            if (_existPositionState(batchPositionInfos[i].poolId, ITradingHub.PositionState.OPEN)) break;
            if (_existPositionState(batchPositionInfos[i].poolId, ITradingHub.PositionState.CLOSING) || _existPositionState(batchPositionInfos[i].poolId, ITradingHub.PositionState.OVERDRAWN)) {
                poolGuardian.setStateFlag(batchPositionInfos[i].poolId, IPoolGuardian.PoolStatus.LIQUIDATING);
            } else {
                poolGuardian.setStateFlag(batchPositionInfos[i].poolId, IPoolGuardian.PoolStatus.ENDED);
            }
        }
    }

    function deliver(ITradingHub.BatchPositionInfo[] memory batchPositionInfos) external override onlyGrabber {
        uint256 positionCount = batchPositionInfos.length;
        for (uint256 i = 0; i < positionCount; i++) {
            (, address strToken, IPoolGuardian.PoolStatus poolStatus) = poolGuardian.getPoolInfo(batchPositionInfos[i].poolId);
            require(poolStatus == IPoolGuardian.PoolStatus.LIQUIDATING, "TradingHub: Pool is not liquidating");
            (, , , , , , , uint256 endBlock, , , , ) = IPool(strToken).getInfo();
            require(block.number > endBlock.add(1000), "TradingHub: Pool is not delivering");
            for (uint256 j = 0; j < batchPositionInfos[i].positions.length; j++) {
                PositionInfo storage positionInfo = positionInfoMap[batchPositionInfos[i].positions[j]];
                require(positionInfo.positionState == PositionState.OVERDRAWN, "TradingHub: Position is not overdrawn");
                _updatePositionState(batchPositionInfos[i].positions[j], PositionState.CLOSED);
            }
            if (batchPositionInfos[i].positions.length > 0) {
                IPool(strToken).deliver(true);
            }
            if (_existPositionState(batchPositionInfos[i].poolId, ITradingHub.PositionState.OVERDRAWN)) break;
            poolGuardian.setStateFlag(batchPositionInfos[i].poolId, IPoolGuardian.PoolStatus.ENDED);
        }
    }

    function updatePositionState(address position, PositionState positionState) external override {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.AUCTION_HALL) || msg.sender == shorterBone.getAddress(AllyLibrary.VAULT_BUTLER), "TradingHub: Caller is neither auctionHall nor vaultButler");
        _updatePositionState(position, positionState);
    }

    function _duplicatedOpenPosition(uint256 poolId, address user) internal view returns (address position) {
        for (uint256 i = 0; i < userPositionSize[user]; i++) {
            PositionCube storage positionCube = userPositions[user][i];
            if (positionCube.poolId == poolId && positionInfoMap[positionCube.addr].positionState == PositionState.OPEN) {
                return positionCube.addr;
            }
        }
    }

    function _updatePositionState(address position, PositionState positionState) internal {
        if (positionState == PositionState.CLOSING) {
            positionBlocks[position].closingBlock = block.number;
            emit PositionClosing(position);
        } else if (positionState == PositionState.OVERDRAWN) {
            positionBlocks[position].overdrawnBlock = block.number;
            emit PositionOverdrawn(position);
        } else if (positionState == PositionState.CLOSED) {
            positionBlocks[position].closedBlock = block.number;
            emit PositionClosed(position);
        }

        positionInfoMap[position].positionState = positionState;
    }

    function _existPositionState(uint256 poolId, ITradingHub.PositionState positionState) internal view returns (bool) {
        uint256 poolPosSize = poolPositionSize[poolId];
        for (uint256 i = 0; i < poolPosSize; i++) {
            if (positionInfoMap[poolPositions[poolId][i]].positionState == positionState) {
                return true;
            }
        }
        return false;
    }

    function getPositionsByAccount(address account, PositionState positionState) external view returns (address[] memory) {
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

    function getPositionsByPoolId(uint256 poolId, PositionState positionState) external view override returns (address[] memory) {
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

    function getPositionsByState(PositionState positionState) external view override returns (address[] memory) {
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

    function setDexCenter(address newDexCenter) external isKeeper {
        require(newDexCenter != address(0), "TradingHub: NewDexCenter is zero address");
        dexCenter = IDexCenter(newDexCenter);
    }

    function setPriceOracle(address newPriceOracle) external isKeeper {
        require(newPriceOracle != address(0), "TradingHub: NewPriceOracle is zero address");
        priceOracle = IPriceOracle(newPriceOracle);
    }
}
