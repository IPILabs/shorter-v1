// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../TitanCoreStorage.sol";

contract GovRewardModelStorage is TitanCoreStorage {
    bool internal _initialized;
    uint256 internal ApyPoint;
    address public ipistrToken;
    address public farming;
    address public committee;
    mapping(address => uint256) internal userLastRewardBlock;
}
