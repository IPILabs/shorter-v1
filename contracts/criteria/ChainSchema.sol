// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @notice Configuration meters for various chain deployment
/// @author IPILabs
contract ChainSchema {
    bool private _initialized;

    string internal _chainShortName;
    string internal _chainFullName;
    uint256 internal _blocksPerDay;
    uint256 internal _secondsPerBlock;

    event ChainConfigured(address indexed thisAddr, string shortName, string fullName, uint256 secondsPerBlock);

    modifier chainReady() {
        require(_initialized, "ChainSchema: Waiting to be configured");
        _;
    }

    function configChain(
        string memory shortName,
        string memory fullName,
        uint256 secondsPerBlock
    ) public {
        require(!_initialized, "ChainSchema: Reconfiguration is not allowed");
        require(secondsPerBlock > 0, "ChainSchema: Invalid secondsPerBlock");

        _chainShortName = shortName;
        _chainFullName = fullName;
        _blocksPerDay = uint256(24 * 60 * 60) / secondsPerBlock;
        _secondsPerBlock = secondsPerBlock;
        _initialized = true;

        emit ChainConfigured(address(this), shortName, fullName, secondsPerBlock);
    }

    function chainShortName() public view returns (string memory) {
        return _chainShortName;
    }

    function chainFullName() public view returns (string memory) {
        return _chainFullName;
    }

    function blocksPerDay() public view returns (uint256) {
        return _blocksPerDay;
    }

    function secondsPerBlock() public view returns (uint256) {
        return _secondsPerBlock;
    }

    function getChainId() public pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
