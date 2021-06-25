// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../criteria/Affinity.sol";
import "../criteria/ChainSchema.sol";
import "./UpgradeabilityProxy.sol";

/// @notice Top level proxy for delegate
contract TitanProxy is Affinity, ChainSchema, Pausable, UpgradeabilityProxy {
    constructor(address _SAVIOR, address implementationContract) public Affinity(_SAVIOR) UpgradeabilityProxy(implementationContract) {}

    function version() public view returns (uint256) {
        return _version();
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    function upgradeTo(uint256 newVersion, address newImplementation) public isManager {
        _upgradeTo(newVersion, newImplementation);
    }

    function setPaused() public isManager {
        _pause();
    }

    function setUnPaused() public isManager {
        _unpause();
    }

    receive() external payable {}
}
