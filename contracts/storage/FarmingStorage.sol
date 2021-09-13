// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../interfaces/IShorterBone.sol";
import "../interfaces/v1/model/IFarmingRewardModel.sol";
import "../interfaces/v1/model/ITradingRewardModel.sol";
import "../interfaces/v1/model/IPoolRewardModel.sol";
import "../interfaces/v1/model/IGovRewardModel.sol";
import "../interfaces/v1/model/IVoteRewardModel.sol";
import "./TitanCoreStorage.sol";

contract FarmingStorage is TitanCoreStorage {
    bool internal _initialized;
    address public lpToken;
    bytes32 internal signature;

    ITradingRewardModel public tradingRewardModel;
    IFarmingRewardModel public farmingRewardModel;
    IGovRewardModel public govRewardModel;
    IPoolRewardModel public poolRewardModel;
    IVoteRewardModel public voteRewardModel;

    mapping(address => uint256) public userStakedAmount;
}
