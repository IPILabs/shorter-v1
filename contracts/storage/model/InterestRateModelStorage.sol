// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../TitanCoreStorage.sol";
import "../../interfaces/v1/IPoolGuardian.sol";

contract InterestRateModelStorage is TitanCoreStorage {
    bool internal _initialized;

    // 0.125 1e6
    uint256 public multiplier;
    // 0.5 1e6
    uint256 public jumpMultiplier;
    // 0.8 1e18
    uint256 public kink;
    // 1e5 => 10%
    uint256 public annualized;

    IPoolGuardian public poolGuardian;
}
