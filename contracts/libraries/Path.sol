// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./BytesLib.sol";

library Path {
    using BytesLib for bytes;

    /// @dev The length of the bytes encoded address
    uint256 private constant ADDR_SIZE = 20;

    /// @dev The length of the bytes encoded fee
    uint256 private constant FEE_SIZE = 3;

    /// @dev The offset of a single token address and pool fee
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;

    function getTokenIn(bytes memory path) internal pure returns (address tokenIn) {
        tokenIn = path.toAddress(0);
        // tokenIn = abi.decode(path.slice(0, ADDR_SIZE), (address));
    }

    function getTokenOut(bytes memory path) internal pure returns (address tokenOut) {
        tokenOut = path.toAddress(path.length - ADDR_SIZE);
        // tokenOut = abi.decode(path.slice((path.length - ADDR_SIZE), path.length), (address));
    }

    function getRouter(bytes memory path) internal pure returns (address[] memory router) {
        uint256 numPools = ((path.length - ADDR_SIZE) / NEXT_OFFSET);
        router = new address[](numPools + 1);

        for (uint256 i = 0; i < numPools; i++) {
            router[i] = path.toAddress(NEXT_OFFSET * i);
        }

        router[numPools] = path.toAddress(path.length - ADDR_SIZE);
    }
}
