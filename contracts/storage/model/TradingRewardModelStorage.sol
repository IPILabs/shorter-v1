// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../TitanCoreStorage.sol";
import "../../interfaces/v1/IPoolGuardian.sol";
import "../../oracles/IPriceOracle.sol";

contract TradingRewardModelStorage is TitanCoreStorage {
    bool internal _initialized;

    address public ipistrToken;
    address public farming;
    IPoolGuardian public poolGuardian;
    IPriceOracle public priceOracle;

    mapping(uint256 => mapping(address => uint256)) public tradingRewardDebt;
}
