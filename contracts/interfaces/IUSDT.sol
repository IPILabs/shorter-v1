// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @dev Enhanced IERC20 interface
interface IUSDT {
    function approve(address spender, uint256 amount) external;

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external;

    function allowance(address owner, address spender) external view returns (uint256);
}
