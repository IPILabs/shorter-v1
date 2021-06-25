// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @notice Interface of Affinity
interface IAffinity {
    function allow(
        address token,
        address spender,
        uint256 amount
    ) external;

    function allowTetherToken(
        address token,
        address spender,
        uint256 amount
    ) external;
}
