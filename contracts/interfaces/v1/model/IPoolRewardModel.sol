// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../../IShorterBone.sol";
import "./IRewardModel.sol";

/// @notice Interfaces of PoolRewardModel
interface IPoolRewardModel {
    function harvest(
        address user,
        uint256[] memory stakedPools,
        uint256[] memory createPools,
        uint256[] memory votePools
    ) external returns (uint256 rewards);

    function pendingReward(address user)
        external
        view
        returns (
            uint256 stakedRewards,
            uint256 creatorRewards,
            uint256 voteRewards,
            uint256[] memory stakedPools,
            uint256[] memory createPools,
            uint256[] memory votePools
        );

    function harvestByStrToken(
        uint256 poolId,
        address user,
        uint256 amount
    ) external;
}
