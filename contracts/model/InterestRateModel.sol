// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../proxy/TitanProxy.sol";
import "../storage/model/InterestRateModelStorage.sol";

contract InterestRateModel is TitanProxy, InterestRateModelStorage {
    constructor(address _SAVIOR, address _implementationContract) public TitanProxy(_SAVIOR, _implementationContract) {}
}
