// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

interface IShorterFactory {
    function createStrPool(uint256 poolId) external returns (address strToken);

    function createOthers(bytes memory code, uint256 salt) external returns (address _contractAddr);
}
