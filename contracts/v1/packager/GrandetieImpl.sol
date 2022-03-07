// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../../util/Ownable.sol";

contract GrandetieImpl is Ownable {
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("approve(address,uint256)")));

    function approve(
        address token,
        address spender,
        uint256 amount
    ) external onlyOwner returns (bool) {
        (bool success, ) = token.call(abi.encodeWithSelector(SELECTOR, spender, amount));
        require(success, "WrappedRouter: Approve failed");
    }
}
