// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../../util/Ownable.sol";
import "../../proxy/UpgradeabilityProxy.sol";

contract Grandetie is UpgradeabilityProxy, Ownable {
    constructor(address implementationContract, address newOwner) public UpgradeabilityProxy(implementationContract) {
        setOwner(newOwner);
    }

    receive() external payable {}
}
