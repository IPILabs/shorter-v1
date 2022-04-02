// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/ISRC20.sol";

contract Rescuable {
    using SafeToken for ISRC20;

    address public immutable committeeContract;

    modifier onlyCommittee() {
        require(msg.sender == committeeContract, "Rescuable: Caller is not Committee");
        _;
    }

    constructor(address _committee) public {
        committeeContract = _committee;
    }

    function emergencyWithdraw(address account, address[] memory tokens) external onlyCommittee {
        for (uint256 i = 0; i < tokens.length; i++) {
            ISRC20 token = ISRC20(tokens[i]);
            uint256 _balanceOf = token.balanceOf(address(this));
            ISRC20(token).safeTransfer(account, _balanceOf);
        }
    }

    function killSelf(address account) external onlyCommittee {
        selfdestruct(payable(account));
    }
}
