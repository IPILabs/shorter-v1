// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./interfaces/IShorterFactory.sol";
import "./interfaces/IShorterBone.sol";
import "./proxy/Pool.sol";

contract ShorterFactory is Affinity, IShorterFactory {
    mapping(uint256 => address) public getPoolAddr;
    address public shorterBone;

    event Deployed(address indexed addr, uint256 salt);

    modifier onlyPoolGuardian() {
        require(msg.sender == IShorterBone(shorterBone).getAddress(AllyLibrary.POOL_GUARDIAN), "ShorterFactory: Caller is not PoolGuardian");
        _;
    }

    constructor(address _SAVIOR) public Affinity(_SAVIOR) {}

    function createStrPool(uint256 poolId, address _poolGuardian) external override onlyPoolGuardian returns (address strPool) {
        if (getPoolAddr[poolId] != address(0)) return getPoolAddr[poolId];
        bytes memory bytecode = type(Pool).creationCode;
        bytecode = abi.encodePacked(bytecode, abi.encode(SAVIOR, shorterBone, _poolGuardian));
        assembly {
            strPool := create2(0, add(bytecode, 0x20), mload(bytecode), poolId)
            if iszero(extcodesize(strPool)) {
                revert(0, 0)
            }
        }

        getPoolAddr[poolId] = strPool;
    }

    function createOthers(bytes memory code, uint256 salt) external override isSavior returns (address _contractAddr) {
        assembly {
            _contractAddr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(_contractAddr)) {
                revert(0, 0)
            }
        }

        emit Deployed(_contractAddr, salt);
    }

    function setShorterBone(address newShorterBone) external {
        require(shorterBone == address(0), "ShorterFactory: shorterBone is not zero address");
        shorterBone = newShorterBone;
    }
}
