// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./IRewardModel.sol";

/// @notice Interfaces of FarmingRewardModel
interface IFarmingRewardModel {
    function harvest(address user) external returns (uint256 rewards);

    function pendingReward(address user) external view returns (uint256 unLockRewards, uint256 rewards);
}
