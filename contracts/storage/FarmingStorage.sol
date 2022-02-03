// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../interfaces/IShorterBone.sol";
import "../interfaces/v1/model/IFarmingRewardModel.sol";
import "../interfaces/v1/model/ITradingRewardModel.sol";
import "../interfaces/v1/model/IPoolRewardModel.sol";
import "../interfaces/v1/model/IGovRewardModel.sol";
import "../interfaces/v1/model/IVoteRewardModel.sol";
import "../interfaces/uniswapv3/IUniswapV3Pool.sol";
import "../interfaces/uniswapv3/INonfungiblePositionManager.sol";
import "./TitanCoreStorage.sol";

contract FarmingStorage is TitanCoreStorage {
    struct PoolInfo {
        address token0;
        address token1;
        uint256 fee;
        uint256 midPrice;
        uint256 lowerPrice;
        uint256 upperPrice;
        uint256 token0PerLp;
        uint256 token1PerLp;
    }

    struct UserInfo {
        uint256 amount;
        uint256 token0Debt;
        uint256 token1Debt;
    }

    bool internal _initialized;
    bytes32 internal signature;
    address public ipistrToken;
    uint256 public _tokenId;

    ITradingRewardModel public tradingRewardModel;
    IFarmingRewardModel public farmingRewardModel;
    IGovRewardModel public govRewardModel;
    IPoolRewardModel public poolRewardModel;
    IVoteRewardModel public voteRewardModel;
    IUniswapV3Pool public uniswapV3Pool;
    INonfungiblePositionManager public nonfungiblePositionManager;

    mapping(address => UserInfo) public userInfoMap;
    mapping(uint256 => PoolInfo) public poolInfoMap;
    mapping(address => uint256) public userStakedAmount;
}
