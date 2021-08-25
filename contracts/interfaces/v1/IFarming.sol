// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @notice Interfaces of Farming
interface IFarming {
    function getUserStakedAmount(address user) external view returns (uint256 userStakedAmount);

    event Stake(address indexed user, uint256 amount);
    event UnStake(address indexed user, uint256 amount);
}
