// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../../util/Ownable.sol";
import "../../proxy/UpgradeabilityProxy.sol";
import "../Rescuable.sol";

contract Grandetie is UpgradeabilityProxy, Ownable, Rescuable {
    constructor(
        address implementationContract,
        address newOwner,
        address _committee
    ) public UpgradeabilityProxy(implementationContract) Rescuable(_committee) {
        setOwner(newOwner);
    }

    receive() external payable {}
}
