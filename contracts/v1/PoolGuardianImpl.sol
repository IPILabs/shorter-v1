// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../interfaces/IPool.sol";
import "../interfaces/v1/IWrapRouter.sol";
import "../criteria/ChainSchema.sol";
import "../storage/TheiaStorage.sol";
import "../util/BoringMath.sol";

contract PoolGuardianImpl is ChainSchema, TheiaStorage, IPoolGuardian {
    using BoringMath for uint256;

    address public override WrappedEtherAddr;

    modifier onlyCommittee() {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.COMMITTEE), "PoolGuardian: Caller is not Committee");
        _;
    }

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    function initialize(
        address _shorterBone,
        address _WrappedEtherAddr,
        uint256[] memory _levelScoresDef,
        uint256[] memory _leverageThresholds
    ) external isSavior {
        require(!_initialized, "PoolGuardian: Already initialized");
        require(_levelScoresDef.length == _leverageThresholds.length, "PoolGuardian: Invalid leverage params");
        shorterBone = IShorterBone(_shorterBone);
        levelScoresDef = _levelScoresDef;
        leverageThresholds = _leverageThresholds;
        WrappedEtherAddr = _WrappedEtherAddr;
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
        require(_checkLeverageValid(stakedToken, leverage), "PoolGuardian: Invalid leverage");
        address strToken = AllyLibrary.getShorterFactory(shorterBone).createStrPool(poolId, address(this));
        address tradingHub = shorterBone.getAddress(AllyLibrary.TRADING_HUB);
        address poolRewardModel = shorterBone.getAddress(AllyLibrary.POOL_REWARD);
        IPool(strToken).initialize(creator, stakedToken, stableToken, wrapRouter, tradingHub, poolRewardModel, poolId, leverage, durationDays, blocksPerDay(), WrappedEtherAddr);
        poolInfoMap[poolId] = PoolInfo({stakedToken: stakedToken, stableToken: stableToken, strToken: strToken, stateFlag: PoolStatus.GENESIS});
        poolIds.push(poolId);
        createPoolIds[creator].push(poolId);
    }

    function listPool(uint256 poolId) external override onlyCommittee {
        PoolInfo storage pool = poolInfoMap[poolId];
        IPool(pool.strToken).list();
        pool.stateFlag = IPoolGuardian.PoolStatus.RUNNING;
    }

    function changeLeverageThresholds(uint256[] memory _leverageThresholds) external onlyCommittee {
        leverageThresholds = _leverageThresholds;
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

    function setPoolInvokers(bytes4[] memory _sigs, address _implementation) external isSavior {
        for (uint256 i = 0; i < _sigs.length; i++) {
            poolInvokers[_sigs[i]] = _implementation;
        }
        emit PoolInvokerChanged(msg.sender, _implementation, _sigs);
    }

    function setWrapRouter(address newWrapRouter) external isKeeper {
        require(newWrapRouter != address(0));
        wrapRouter = newWrapRouter;
    }

    function _checkLeverageValid(address stakedToken, uint256 leverage) internal view returns (bool res) {
        (, , uint256 tokenRatingScore) = shorterBone.getTokenInfo(stakedToken);
        for (uint256 i = 0; i < levelScoresDef.length; i++) {
            if (tokenRatingScore >= levelScoresDef[i] && leverage <= leverageThresholds[i]) {
                return true;
            }
        }
        return false;
    }

    function queryPools(address stakedToken, PoolStatus status) external view override returns (uint256[] memory) {
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

    /// @notice Switch a pool's stateFlag to HIDING or Display.
    function setStateFlag(uint256 poolId, PoolStatus status) external override isManager {
        PoolInfo storage pool = poolInfoMap[poolId];
        pool.stateFlag = status;

        IPool(pool.strToken).setStateFlag(status);
    }

    function getPoolInvokers(bytes4 _sig) external view override returns (address) {
        return poolInvokers[_sig];
    }
}
