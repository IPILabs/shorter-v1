// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./TitanCoreStorage.sol";

contract TokenStorage is TitanCoreStorage {
    mapping(address => uint256) internal _lockedBalances;
}
