// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

interface IDexCenter {
    struct SellShortParams {
        bool isSwapRouterV3;
        uint256 amountIn;
        uint256 amountOutMin;
        address swapRouter;
        address to;
        bytes path;
    }

    struct BuyCoverParams {
        bool isSwapRouterV3;
        bool isTetherToken;
        uint256 amountOut;
        uint256 amountInMax;
        address swapRouter;
        address to;
        bytes path;
    }

    function getSwapRouterWhiteList(address swapRouter) external view returns (bool);

    function isSwapRouterV3(address swapRouter) external view returns (bool);

    function getV2Price(address swapRouter, address[] memory path) external view returns (uint256 price);

    function getV3Price(
        address swapRouter,
        address[] memory path,
        uint24[] memory fees
    ) external view returns (uint256 price);
}
