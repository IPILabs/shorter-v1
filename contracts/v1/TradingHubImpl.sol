// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "./Rescuable.sol";
import "../libraries/Path.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/IStrPool.sol";
import "../interfaces/IDexCenter.sol";
import "../criteria/ChainSchema.sol";
import "../storage/AresStorage.sol";
import "../util/BoringMath.sol";

/// @notice Hub for dealing with orders, positions and traders
contract TradingHubImpl is Rescuable, ChainSchema, Pausable, AresStorage, ITradingHub {
    using BoringMath for uint256;
    using Path for bytes;

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    modifier onlySwapRouter(address _swapRouter) {
        require(dexCenter.getSwapRouterWhiteList(_swapRouter), "TradingHub: Invalid SwapRouter");
        _;
    }

    function checkPath(
        bytes memory path,
        address tokenIn,
        address tokenOut
    ) internal pure {
        require(path.getTokenIn() == tokenIn, "TradingHub: Invalid tokenIn");
        require(path.getTokenOut() == tokenOut, "TradingHub: Invalid tokenOut");
    }

    function sellShort(
        uint256 poolId,
        uint256 amount,
        uint256 amountOutMin,
        address swapRouter,
        bytes memory path
    ) external whenNotPaused onlyEOA onlySwapRouter(swapRouter) {
        PoolInfo memory pool = getPoolInfo(poolId);
        require(path.getTokenIn() == address(pool.stakedToken), "TradingHub: Invalid tokenIn");
        require(path.getTokenOut() == address(pool.stableToken), "TradingHub: Invalid tokenOut");
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
        IStrPool(pool.strToken).borrow(dexCenter.isSwapRouterV3(swapRouter), address(dexCenter), swapRouter, position, msg.sender, amount, amountOutMin, path);
    }

    function buyCover(
        uint256 poolId,
        uint256 amount,
        uint256 amountInMax,
        address swapRouter,
        bytes memory path
    ) external whenNotPaused onlyEOA {
        PoolInfo memory pool = getPoolInfo(poolId);
        bool isSwapRouterV3 = dexCenter.isSwapRouterV3(swapRouter);
        if (isSwapRouterV3) {
            require(path.getTokenIn() == address(pool.stakedToken), "TradingHub: Invalid tokenIn");
            require(path.getTokenOut() == address(pool.stableToken), "TradingHub: Invalid tokenOut");
        } else {
            require(path.getTokenIn() == address(pool.stableToken), "TradingHub: Invalid tokenIn");
            require(path.getTokenOut() == address(pool.stakedToken), "TradingHub: Invalid tokenOut");
        }

        address position = _duplicatedOpenPosition(poolId, msg.sender);
        require(position != address(0), "TradingHub: Position not found");

        bool isClosed = IStrPool(pool.strToken).repay(isSwapRouterV3, shorterBone.TetherToken() == address(pool.stableToken), address(dexCenter), swapRouter, position, msg.sender, amount, amountInMax, path);

        if (isClosed) {
            _updatePositionState(position, PositionState.CLOSED);
        } else {
            emit PositionDecreased(poolId, msg.sender, position, amount);
        }
    }

    function getPositionInfo(address position)
        external
        view
        override
        returns (
            uint256 poolId,
            address strToken,
            uint256 closingBlock,
            PositionState positionState
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

    function initialize(address _shorterBone, address _poolGuardian) external isKeeper {
        require(!_initialized, "TradingHub: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
        _initialized = true;
    }

    function getPoolInfo(uint256 poolId) internal view returns (PoolInfo memory poolInfo) {
        (, address strToken, ) = poolGuardian.getPoolInfo(poolId);
        (address creator, address stakedToken, address stableToken, , uint256 leverage, uint256 durationDays, uint256 startBlock, uint256 endBlock, uint256 id, uint256 stakedTokenDecimals, uint256 stableTokenDecimals, IPoolGuardian.PoolStatus stateFlag) = IStrPool(strToken).getInfo();
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

    function executePositions(address[] memory positions) external override {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.GRAB_REWARD), "TradingHub: Caller is not Grabber");
        for (uint256 i = 0; i < positions.length; i++) {
            PositionInfo storage positionInfo = positionInfoMap[positions[i]];
            require(positionInfo.positionState == PositionState.OPEN, "TradingHub: Not a open position");

            PositionState positionState = IStrPool(positionInfo.strToken).updatePositionToAuctionHall(positions[i]);
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

    function batchClosePositions(uint256 poolId) external isManager {
        (, address strToken, IPoolGuardian.PoolStatus poolStatus) = poolGuardian.getPoolInfo(poolId);
        require(poolStatus == IPoolGuardian.PoolStatus.RUNNING, "TradingHub: Pool is not running");
        uint256 poolPosSize = poolPositionSize[poolId];
        address[] memory posContainer = new address[](poolPosSize);

        uint256 resPosCount;
        for (uint256 i = 0; i < poolPosSize; i++) {
            address position = poolPositions[poolId][i];
            PositionInfo storage positionInfo = positionInfoMap[position];
            if (positionInfo.positionState == PositionState.OPEN) {
                positionInfo.positionState = PositionState.CLOSING;
                posContainer[resPosCount++] = position;
            }
        }

        if (resPosCount == 0) {
            poolGuardian.setStateFlag(poolId, IPoolGuardian.PoolStatus.ENDED);
            return;
        }

        address[] memory resPositions = new address[](resPosCount);
        for (uint256 i = 0; i < resPosCount; i++) {
            resPositions[i] = posContainer[i];
        }

        IStrPool(strToken).batchUpdateFundingFee(resPositions);
        poolGuardian.setStateFlag(poolId, IPoolGuardian.PoolStatus.LIQUIDATING);
    }

    function delivery(uint256 poolId) external isManager {
        (, address strToken, IPoolGuardian.PoolStatus poolStatus) = poolGuardian.getPoolInfo(poolId);
        require(poolStatus == IPoolGuardian.PoolStatus.LIQUIDATING, "TradingHub: Pool is not liquidating");
        uint256 poolPosSize = poolPositionSize[poolId];

        bool isDelivery = false;
        for (uint256 i = 0; i < poolPosSize; i++) {
            address position = poolPositions[poolId][i];
            PositionInfo storage positionInfo = positionInfoMap[position];
            if (positionInfo.positionState == PositionState.OVERDRAWN) {
                isDelivery = true;
                positionInfo.positionState = PositionState.CLOSED;
            }
        }

        if (isDelivery) {
            poolGuardian.setStateFlag(poolId, IPoolGuardian.PoolStatus.RECOVER);
        } else {
            poolGuardian.setStateFlag(poolId, IPoolGuardian.PoolStatus.ENDED);
        }

        IStrPool(strToken).delivery(isDelivery);
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

    function getPositionsByAccount(address account, PositionState positionState) public view returns (address[] memory) {
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

    function getPositionsByPoolId(uint256 poolId, PositionState positionState) public view override returns (address[] memory) {
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

    function getPositionsByState(PositionState positionState) public view override returns (address[] memory) {
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

    function setDexCenter(address newDexCenter) public isManager {
        dexCenter = IDexCenter(newDexCenter);
    }

    function setPriceOracle(address newPriceOracle) public isManager {
        priceOracle = IPriceOracle(newPriceOracle);
    }
}
