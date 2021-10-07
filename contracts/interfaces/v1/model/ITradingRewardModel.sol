// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./IRewardModel.sol";

/// @notice Interfaces of TradingRewardModel
interface ITradingRewardModel {
    function pendingReward(address trader) external view returns (uint256 rewards, uint256[] memory poolIds);

    function harvest(address trader, uint256[] memory poolIds) external returns (uint256 rewards);
}
