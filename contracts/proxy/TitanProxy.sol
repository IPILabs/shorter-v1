// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../criteria/ChainSchema.sol";
import "./UpgradeabilityProxy.sol";

/// @notice Top level proxy for delegate
contract TitanProxy is ChainSchema, UpgradeabilityProxy {
    event Upgraded(uint256 indexed version, address indexed implementation);

    constructor(address _SAVIOR, address implementationContract) public ChainSchema(_SAVIOR) UpgradeabilityProxy(implementationContract) {}

    function version() public view returns (uint256) {
        return _version();
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    function upgradeTo(uint256 newVersion, address newImplementation) external isSavior {
        _upgradeTo(newVersion, newImplementation);
        emit Upgraded(newVersion, newImplementation);
    }

    function setSecondsPerBlock(uint256 newSecondsPerBlock) external isKeeper {
        _secondsPerBlock = newSecondsPerBlock;
    }

    receive() external payable {}
}
