// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./libraries/AllyLibrary.sol";
import "./interfaces/IShorterFactory.sol";
import "./interfaces/IShorterBone.sol";
import "./proxy/Pool.sol";

contract ShorterFactory is Affinity, IShorterFactory {
    using AllyLibrary for IShorterBone;

    mapping(uint256 => address) public getPoolAddr;
    IShorterBone public shorterBone;

    event Deployed(address indexed addr, uint256 salt);

    constructor(address _SAVIOR) public Affinity(_SAVIOR) {}

    function createStrPool(uint256 poolId) external override returns (address strPool) {
        require(msg.sender == shorterBone.getPoolGuardian(), "ShorterFactory: Caller is not PoolGuardian");
        if (getPoolAddr[poolId] != address(0)) return getPoolAddr[poolId];
        bytes memory bytecode = type(Pool).creationCode;
        bytecode = abi.encodePacked(bytecode, abi.encode(SAVIOR, shorterBone, msg.sender));
        assembly {
            strPool := create2(0, add(bytecode, 0x20), mload(bytecode), poolId)
            if iszero(extcodesize(strPool)) {
                revert(0, 0)
            }
        }

        getPoolAddr[poolId] = strPool;
    }

    function createOthers(bytes memory code, uint256 salt) external override returns (address _contractAddr) {
        assembly {
            _contractAddr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(_contractAddr)) {
                revert(0, 0)
            }
        }

        emit Deployed(_contractAddr, salt);
    }

    function setShorterBone(address shorterBoneAddr) external isSavior {
        require(shorterBoneAddr != address(0), "ShorterFactory: shorterBone is not zero address");
        shorterBone = IShorterBone(shorterBoneAddr);
    }
}
