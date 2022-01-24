// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

library PermitLibrary {
    // keccak256("Permit(address owner,address spender,uint256 amount,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_SIGNATURE_HASH = keccak256("Permit(address owner,address spender,uint256 amount,uint256 nonce,uint256 deadline)");

    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 public constant EIP712_DOMAIN_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function getChainId() public pure returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }

        return id;
    }

    function domainSeparator(
        string memory name,
        string memory version,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_HASH, keccak256(bytes(name)), keccak256(bytes(version)), getChainId(), verifyingContract));
    }

    function getPermitMessageHash(
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes32 domainSperator
    ) internal pure returns (bytes32 messageHash) {
        bytes32 _messageHash = keccak256(abi.encode(PERMIT_SIGNATURE_HASH, owner, spender, amount, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainSperator, _messageHash));
    }

    function getSigner(
        bytes memory signatures,
        uint256 pos,
        bytes32 messageHash
    ) internal pure returns (address _signer) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            let signaturePos := mul(0x41, pos)

            r := mload(add(signatures, add(signaturePos, 0x20)))
            s := mload(add(signatures, add(signaturePos, 0x40)))
            v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
        }

        require(v != 0, "PermitLibrary: Caller is a contract");
        require(v != 1, "PermitLibrary: Only supports offline signature");

        if (v > 30) {
            _signer = ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)), v - 4, r, s);
        } else {
            _signer = ecrecover(messageHash, v, r, s);
        }
    }
}
