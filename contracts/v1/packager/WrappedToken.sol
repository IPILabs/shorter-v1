// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../../util/Ownable.sol";
import "../../proxy/UpgradeabilityProxy.sol";

contract WrappedToken is UpgradeabilityProxy, Ownable {
    constructor(address implementationContract) public UpgradeabilityProxy(implementationContract) {}

    receive() external payable {}
}
