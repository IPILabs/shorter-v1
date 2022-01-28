// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

interface IWrapRouter {
    function wrap(address token, uint256 amount) external;

    function unwrap(address token, uint256 amount) external;

    function getInherit(address token) external view returns(address wrappedToken);
}
