// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/ISRC20.sol";
import "../criteria/Affinity.sol";

contract Rescuable is Affinity {
    constructor(address _SAVIOR) public Affinity(_SAVIOR) {}

    function killSelf() public isKeeper {
        selfdestruct(msg.sender);
    }
}
