// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @notice Interfaces of BaseReward model
interface IRewardModel {
    function pendingReward(address user) external view returns (uint256 _reward);

    function harvest(address user) external returns (uint256 rewards);
}
