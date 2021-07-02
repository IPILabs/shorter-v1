// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./interfaces/IShorterFactory.sol";
import "./proxy/StrPool.sol";
import "./v1/Rescuable.sol";

contract ShorterFactory is Rescuable, IShorterFactory {
    mapping(uint256 => address) public getStrToken;
    address[] public allStrTokens;
    address public shorterBone;

    event Deployed(address indexed addr, uint256 salt);

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function createStrPool(uint256 poolId, address _poolGuardian) external override isKeeper returns (address strToken) {
        if (getStrToken[poolId] != address(0)) return getStrToken[poolId];
        bytes memory bytecode = type(StrPool).creationCode;
        bytecode = abi.encodePacked(bytecode, abi.encode(SAVIOR, shorterBone, _poolGuardian));
        assembly {
            strToken := create2(0, add(bytecode, 0x20), mload(bytecode), poolId)
            if iszero(extcodesize(strToken)) {
                revert(0, 0)
            }
        }

        getStrToken[poolId] = strToken;
    }

    function createOthers(bytes memory code, uint256 salt) external override isKeeper returns (address _contractAddr) {
        assembly {
            _contractAddr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(_contractAddr)) {
                revert(0, 0)
            }
        }

        emit Deployed(_contractAddr, salt);
    }

    function setShorterBone(address newShorterBone) external isKeeper {
        shorterBone = newShorterBone;
    }
}
