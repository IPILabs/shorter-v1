// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

// import "../proxy/TitanProxy.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../criteria/Affinity.sol";
import "../storage/StrPoolStorage.sol";

contract StrPool is Affinity, Pausable, StrPoolStorage {
    constructor(
        address _SAVIOR,
        address _shorterBone,
        address _poolGuardian
    ) public Affinity(_SAVIOR) {
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
    }

    fallback() external payable {
        address implementation = poolGuardian.getStrPoolImplementations(msg.sig);

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
}
