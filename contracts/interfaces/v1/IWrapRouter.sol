// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

interface IWrapRouter {
    function wrappable(
        address token,
        address strPool,
        address account,
        uint256 amount,
        uint256 value
    ) external view returns (address);

    function getUnwrappableAmount(
        address account,
        address token,
        uint256 amount
    ) external view returns (address stakedToken);

    function getUnwrappableAmountByPercent(
        uint256 percent,
        address account,
        address token,
        uint256 amount,
        uint256 totalBorrowAmount
    )
        external
        view
        returns (
            address stakedToken,
            uint256 withdrawAmount,
            uint256 burnAmount,
            uint256 userShare
        );

    function wrap(
        uint256 poolId,
        address token,
        address account,
        uint256 amount,
        address stakedToken
    ) external;

    function unwrap(
        uint256 poolId,
        address token,
        address account,
        uint256 amount
    ) external returns (address);

    function transferTokenShare(
        uint256 poolId,
        address from,
        address to,
        uint256 amount
    ) external;

    function inherits(address token) external view returns (address wrappedToken);
}
