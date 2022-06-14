// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../libraries/PermitLibrary.sol";
import "../criteria/ChainSchema.sol";
import "../storage/TreasuryStorage.sol";
import "../util/BoringMath.sol";

contract TreasuryImpl is ChainSchema, TreasuryStorage {
    using EnumerableSet for EnumerableSet.AddressSet;
    using BoringMath for uint256;

    // EIP712Domain(uint256 chainId,address verifyingContract)
    bytes32 internal constant DOMAIN_SEPARATOR_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    // SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 nonce)
    bytes32 internal constant SAFE_TX_TYPEHASH = 0x3317c908a134e5c2510760347e7f23b965536b042f3c71282a3d92e04a7b29f5;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    function initialize(address _shorterBone, uint256 _threshold) external isSavior {
        require(!_initialized, "Treasury: Already initialized");
        require(_threshold > 0, "Treasury: Invalid threshold");

        threshold = _threshold;
        shorterBone = IShorterBone(_shorterBone);
        _initialized = true;
    }

    /// @dev Allows to execute a Safe transaction confirmed by required number of owners and then pays the account that submitted the transaction.
    ///      Note: The fees are always transferred, even if the user transaction fails.
    /// @param to Destination address of Safe transaction.
    /// @param value Ether value of Safe transaction.
    /// @param data Data payload of Safe transaction.
    /// @param operation Operation type of Safe transaction.
    /// @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        bytes memory signatures
    ) external payable virtual returns (bool success) {
        bytes32 txHash;

        {
            bytes memory txHashData = encodeTransactionData(to, value, data, operation, nonce);
            nonce++;
            txHash = keccak256(txHashData);
            _checkSignatures(txHash, signatures);
        }

        success = _execute(to, value, data, operation);

        if (!success) {
            revert("Treasury: Execute Exception");
        }
    }

    function setOwner(address[] calldata _owners) external isSavior {
        for (uint256 i = 0; i < _owners.length; i++) {
            _setOwner(_owners[i]);
        }
    }

    function removeOwner(address _owner) external isSavior {
        owners.remove(_owner);
    }

    function getOwners() external view returns (address[] memory) {
        uint256 ownerLength = owners.length();
        address[] memory _owners = new address[](ownerLength);
        for (uint256 i = 0; i < owners.length(); i++) {
            _owners[i] = owners.at(i);
        }
        return _owners;
    }

    function setThreshold(uint256 newThreshold) external isKeeper {
        threshold = newThreshold;
    }

    /// @dev Returns the bytes that are hashed to be signed by owners.
    /// @param to Destination address.
    /// @param value Ether value.
    /// @param data Data payload.
    /// @param operation Operation type.
    /// @param _nonce Transaction nonce.
    /// @return Transaction hash bytes.
    function encodeTransactionData(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 _nonce
    ) public view returns (bytes memory) {
        bytes32 safeTxHash = keccak256(abi.encode(SAFE_TX_TYPEHASH, to, value, keccak256(data), operation, _nonce));
        return abi.encodePacked(bytes1(0x19), bytes1(0x01), _domainSeparator(), safeTxHash);
    }

    /// @dev Returns hash to be signed by owners.
    /// @param to Destination address.
    /// @param value Ether value.
    /// @param data Data payload.
    /// @param operation Operation type.
    /// @param _nonce Transaction nonce.
    /// @return Transaction hash.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 _nonce
    ) external view returns (bytes32) {
        return keccak256(encodeTransactionData(to, value, data, operation, _nonce));
    }

    function _execute(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation
    ) internal returns (bool success) {
        if (operation == Operation.DelegateCall) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := delegatecall(gas(), to, add(data, 0x20), mload(data), 0, 0)
            }
        } else {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
        }
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, getChainId(), this));
    }

    function _setOwner(address _owner) internal {
        owners.add(_owner);
    }

    /**
     * @dev Checks whether the signature provided is valid for the provided data, hash. Will revert otherwise.
     * @param dataHash Hash of the data (could be either a message hash or transaction hash)
     * @param signatures Signature data that should be verified. Can be ECDSA signature, contract signature (EIP-1271) or approved hash.
     */
    function _checkSignatures(bytes32 dataHash, bytes memory signatures) internal view {
        require(signatures.length >= threshold.mul(65), "Treasury: Signatures too short");
        address currentOwner;
        address lastOwner;
        for (uint256 i = 0; i < threshold; i++) {
            currentOwner = PermitLibrary.getSigner(signatures, i, dataHash);
            require(currentOwner > lastOwner && owners.contains(currentOwner) && currentOwner != address(0), "Treasury: Invalid owner");
            lastOwner = currentOwner;
        }
    }
}
