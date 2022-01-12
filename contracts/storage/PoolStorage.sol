// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../interfaces/ISRC20.sol";
import "./TitanCoreStorage.sol";
import "../interfaces/v1/IPoolGuardian.sol";

contract PoolStorage is TitanCoreStorage {
    struct PoolInfo {
        address stakedToken;
        address stableToken;
        address strToken;
        IPoolGuardian.PoolStatus stateFlag;
    }

    uint256[] public poolIds;

    address internal wrapRouter; 
    bool internal _initialized;
    /// @notice Allowed leverage constant array
    uint256[] public leverageAllowedList;

    mapping(address => uint256[]) public createPoolIds;

    mapping(address => uint256) public maxLeverage;

    mapping(uint256 => PoolInfo) public poolInfoMap;

    mapping(bytes4 => address) public strPoolImplementations;

    mapping(address => address) public wrapStakedTokens;
}
