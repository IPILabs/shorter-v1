// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./TitanCoreStorage.sol";

contract TreasuryStorage is TitanCoreStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    enum Operation {
        Call,
        DelegateCall
    }

    uint256 public nonce;
    uint256 public threshold;
    bool internal _initialized;

    EnumerableSet.AddressSet internal owners;
}
