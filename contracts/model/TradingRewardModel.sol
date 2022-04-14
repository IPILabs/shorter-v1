// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../proxy/TitanProxy.sol";
import "../storage/model/TradingRewardModelStorage.sol";

contract TradingRewardModel is TitanProxy, TradingRewardModelStorage {
    constructor(address _SAVIOR, address _implementationContract) public TitanProxy(_SAVIOR, _implementationContract) {}
}
