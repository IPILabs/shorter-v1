// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Proxy} from "./Proxy.sol";

contract UpgradeabilityProxy is Proxy {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0xb4cff3ccade8876c60e81b90f014ea636f99d530646ec67090e1cc8a04636f38;
    bytes32 internal constant VERSION_SLOT = 0xf62412ce1bd823aa31864380419f787378380edf34602844461eeadf8416d534;

    constructor(address implementationContract) public {
        assert(IMPLEMENTATION_SLOT == keccak256("com.ipilabs.proxy.implementation"));

        assert(VERSION_SLOT == keccak256("com.ipilabs.proxy.version"));

        _upgradeTo(1, implementationContract);
    }

    function _implementation() internal view override returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _version() internal view returns (uint256 version) {
        bytes32 slot = VERSION_SLOT;
        assembly {
            version := sload(slot)
        }
    }

    function _upgradeTo(uint256 newVersion, address newImplementation) internal {
        require(Address.isContract(newImplementation), "Non-contract address");

        _setImplementation(newImplementation);
        _setVersion(newVersion);
    }

    function _setImplementation(address newImplementation) internal {
        require(Address.isContract(newImplementation), "Non-contract address");

        bytes32 slot = IMPLEMENTATION_SLOT;

        assembly {
            sstore(slot, newImplementation)
        }
    }

    function _setVersion(uint256 newVersion) internal {
        bytes32 slot = VERSION_SLOT;

        assembly {
            sstore(slot, newVersion)
        }
    }
}
