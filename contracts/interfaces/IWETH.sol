// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @dev Enhanced IWETH interface
interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}
