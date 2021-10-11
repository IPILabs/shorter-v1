// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/AllyLibrary.sol";
import "../interfaces/IStrPool.sol";
import "../interfaces/v1/IWrapRouter.sol";
import "../criteria/ChainSchema.sol";
import "../storage/TheiaStorage.sol";
import "./Rescuable.sol";
import "../util/BoringMath.sol";

contract PoolGuardianImplV1 is Rescuable, ChainSchema, Pausable, TheiaStorage, IPoolGuardian {
    using BoringMath for uint256;

    modifier onlyCommittee() {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.COMMITTEE), "PoolGuardian: Caller is not Committee");
        _;
    }

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function initialize(address _shorterBone) external isKeeper {
        require(!_initialized, "PoolGuardian: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        leverageAllowedList = [1, 2, 5];
        _initialized = true;
        emit PoolGuardianInitiated();
    }

    /// @notice Add a new pool. DO NOT add the pool with identical meters
    function addPool(
        address stakedToken,
        address stableToken,
        address creator,
        uint256 leverage,
        uint256 durationDays,
        uint256 poolId
    ) external override onlyCommittee {
        require(checkLeverageValid(stakedToken, leverage), "PoolGuardian: Invalid leverage");
        address strToken = AllyLibrary.getShorterFactory(shorterBone).createStrPool(poolId, address(this));
        address tradingHub = shorterBone.getAddress(AllyLibrary.TRADING_HUB);
        address poolRewardModel = shorterBone.getAddress(AllyLibrary.POOL_REWARD);
        IStrPool(strToken).initialize(creator, stakedToken, stableToken, wrapRouter, tradingHub, poolRewardModel, poolId, leverage, durationDays);
        poolInfoMap[poolId] = PoolInfo({stakedToken: stakedToken, stableToken: stableToken, strToken: strToken, stateFlag: PoolStatus.GENESIS});
        poolIds.push(poolId);
        createPoolIds[creator].push(poolId);
    }

    function listPool(uint256 poolId) external override onlyCommittee {
        PoolInfo storage pool = poolInfoMap[poolId];
        IStrPool(pool.strToken).listPool(blocksPerDay());
        pool.stateFlag = IPoolGuardian.PoolStatus.RUNNING;
    }

    function getPoolIds() external view override returns (uint256[] memory _poolIds) {
        _poolIds = poolIds;
    }

    function getCreatedPoolIds(address creator) external view returns (uint256[] memory _poolIds) {
        _poolIds = createPoolIds[creator];
    }

    function getPoolInfo(uint256 poolId)
        external
        view
        override
        returns (
            address stakedToken,
            address strToken,
            PoolStatus stateFlag
        )
    {
        PoolInfo storage pool = poolInfoMap[poolId];
        return (pool.stakedToken, pool.strToken, pool.stateFlag);
    }

    function setMaxLeverage(address tokenAddr, uint256 newMaxLeverage) external isManager {
        maxLeverage[tokenAddr] = newMaxLeverage;
    }

    /// @notice Update a pool's stateFlag just for HIDING or Display. Can only be called by the owner.
    function setStateFlag(uint256 poolId, PoolStatus status) external override isManager {
        PoolInfo storage pool = poolInfoMap[poolId];
        pool.stateFlag = status;

        IStrPool(pool.strToken).setStateFlag(status);
        if (status == PoolStatus.RUNNING) {
            emit PoolListed(poolId);
        } else if (status == PoolStatus.ENDED) {
            emit PoolDelisted(poolId);
        }
    }

    function setStrPoolImplementations(bytes4[] memory _sigs, address _implementation) public isManager {
        for (uint256 i = 0; i < _sigs.length; i++) {
            strPoolImplementations[_sigs[i]] = _implementation;
        }
    }

    function setWrapRouter(address newWrapRouter) external isManager {
        wrapRouter = newWrapRouter;
    }

    function checkLeverageValid(address stakedToken, uint256 leverage) internal view returns (bool res) {
        if (maxLeverage[stakedToken] > 0 && leverage <= maxLeverage[stakedToken]) {
            return true;
        }

        for (uint256 i = 0; i < leverageAllowedList.length; i++) {
            if (leverageAllowedList[i] == leverage) {
                return true;
            }
        }

        (, , uint256 multiplier) = shorterBone.getTokenInfo(stakedToken);
        if ((multiplier > 680) && leverage == 10) {
            return true;
        }

        return false;
    }

    function queryPools(address stakedToken, PoolStatus status) public view override returns (uint256[] memory) {
        uint256 poolSize = poolIds.length;
        uint256[] memory poolContainer = new uint256[](poolSize);

        uint256 resPoolCount;
        for (uint256 i = 0; i < poolSize; i++) {
            PoolInfo storage poolInfo = poolInfoMap[poolIds[i]];
            if ((stakedToken == address(0) || poolInfo.stakedToken == stakedToken) && poolInfo.stateFlag == status) {
                poolContainer[resPoolCount++] = poolIds[i];
            }
        }

        uint256[] memory resPools = new uint256[](resPoolCount);
        for (uint256 i = 0; i < resPoolCount; i++) {
            resPools[i] = poolContainer[i];
        }

        return resPools;
    }

    function getStrPoolImplementations(bytes4 _sig) external view override returns (address) {
        return strPoolImplementations[_sig];
    }
}
