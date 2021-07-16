// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

contract EIP712Domain {
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    // See https://eips.ethereum.org/EIPS/eip-191
    string internal constant EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA = "\x19\x01";

    // solhint-disable var-name-mixedcase
    bytes32 internal immutable _DEFAULT_DOMAIN_SEPARATOR;
    uint256 internal immutable _CHAIN_ID;
    string internal constant DOMAIN_NAME = "J";

    /// @dev Calculate the DOMAIN_SEPARATOR
    function _calculateDomainSeparator(uint256 chainId) internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(DOMAIN_NAME)), chainId, address(this)));
    }

    constructor() public {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        _DEFAULT_DOMAIN_SEPARATOR = _calculateDomainSeparator(_CHAIN_ID = chainId);
    }

    /// @dev Return the DOMAIN_SEPARATOR
    // It's named internal to allow making it public from the contract that uses it by creating a simple view function
    // with the desired public name, such as DOMAIN_SEPARATOR or domainSeparator.
    // solhint-disable-next-line func-name-mixedcase
    function domainSeparator() internal view returns (bytes32) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId == _CHAIN_ID ? _DEFAULT_DOMAIN_SEPARATOR : _calculateDomainSeparator(chainId);
    }

    function getDigest(bytes32 hashStruct) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA, domainSeparator(), hashStruct));
    }
}
