// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../TitanCoreStorage.sol";
import "../../interfaces/v1/IFarming.sol";
import "../../interfaces/governance/IIpistrToken.sol";

contract FarmingRewardModelStorage is TitanCoreStorage {
    bool internal _initialized;

    IFarming public farming;

    IIpistrToken public ipistrToken;

    uint256 public maxUnlockSpeed;
    uint256 public maxLpSupply;
    mapping(address => uint256) internal userLastRewardBlock;
}
