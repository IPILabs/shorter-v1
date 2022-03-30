// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../IShorterBone.sol";
import "../../libraries/AllyLibrary.sol";

/// @notice Interfaces of PoolGuardian
interface IPoolGuardian {
    enum PoolStatus {
        GENESIS,
        RUNNING,
        LIQUIDATING,
        DELIVERING,
        ENDED
    }

    function getPoolInfo(uint256 poolId)
        external
        view
        returns (
            address stakedToken,
            address strToken,
            PoolStatus stateFlag
        );

    function addPool(
        address stakedToken,
        address stableToken,
        address creator,
        uint256 leverage,
        uint256 durationDays,
        uint256 poolId
    ) external;

    function listPool(uint256 poolId) external;

    function setStateFlag(uint256 poolId, PoolStatus status) external;

    function queryPools(address stakedToken, PoolStatus status) external view returns (uint256[] memory);

    function getPoolIds() external view returns (uint256[] memory _poolIds);

    function getPoolInvokers(bytes4 _sig) external view returns (address);

    function WrappedEtherAddr() external view returns (address);

    /// @notice Emitted when this contract is deployed
    event PoolGuardianInitiated();

    event PoolStatusChanged(uint256 indexed poolId, PoolStatus poolStatus);

    event PoolInvokerChanged(address keeper, address poolInvoker, bytes4[] sigs);
}
