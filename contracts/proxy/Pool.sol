// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../criteria/ChainSchema.sol";
import "../storage/PoolStorage.sol";

contract Pool is ChainSchema, PoolStorage {
    constructor(
        address _SAVIOR,
        address _shorterBone,
        address _poolGuardian
    ) public ChainSchema(_SAVIOR) {
        shorterBone = IShorterBone(_shorterBone);
        poolGuardian = IPoolGuardian(_poolGuardian);
    }

    fallback() external payable {
        address invoker = poolGuardian.getPoolInvokers(msg.sig);

        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), invoker, 0, calldatasize(), 0, 0)
            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
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
