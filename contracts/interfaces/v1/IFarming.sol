// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @notice Interfaces of Farming
interface IFarming {
    function getUserStakedAmount(address user) external view returns (uint256 userStakedAmount);

    function harvest(uint256 tokenId, address user) external;

    function getTokenId() external view returns (uint256);

    event Stake(address indexed user, uint256 indexed tokenId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event UnStake(address indexed user, uint256 indexed tokenId, uint256 liquidity, uint256 amount0, uint256 amount1);
}
