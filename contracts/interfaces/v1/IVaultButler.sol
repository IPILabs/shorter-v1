// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @notice Interfaces of VaultButler
interface IVaultButler {
    event ExecuteNaginata(address indexed positionAddr, address indexed ruler, uint256 bidSize, uint256 receiveSize);
}
