// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./TitanCoreStorage.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/governance/ICommittee.sol";
import "../oracles/IPriceOracle.sol";

/// @notice Vault
contract VaultStorage is TitanCoreStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct PositionInfo {
        address strToken;
        address stakedToken;
        address stableToken;
        uint256 stakedTokenDecimals;
        uint256 stableTokenDecimals;
        uint256 totalSize;
        uint256 unsettledCash;
        uint256 positionState;
    }

    struct LegacyInfo {
        uint256 bidSize;
        uint256 usedCash;
    }

    mapping(address => LegacyInfo) public legacyInfos;

    bool internal _initialized;
    ICommittee public committee;
    ITradingHub public tradingHub;
    IPriceOracle public priceOracle;
}
