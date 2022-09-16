// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../libraries/AllyLibrary.sol";
import "../interfaces/IShorterBone.sol";
import "../interfaces/v1/IVaultButler.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IWETH.sol";
import "../criteria/ChainSchema.sol";
import "../storage/GaiaStorage.sol";
import "../util/BoringMath.sol";

/// @notice Butler serves the vaults
contract VaultButlerImpl is ChainSchema, GaiaStorage, IVaultButler {
    using BoringMath for uint256;
    using AllyLibrary for IShorterBone;

    uint256 internal constant OVERDRAWN_STATE = 4;

    modifier onlyRuler() {
        require(committee.isRuler(tx.origin), "VaultButler: Caller is not ruler");
        _;
    }

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    function priceOfLegacy(address position) external view returns (uint256) {
        PositionInfo memory positionInfo = _getPositionInfo(position);
        return _priceOfLegacy(positionInfo);
    }

    function executeNaginata(address position, uint256 bidSize) external payable whenNotPaused onlyRuler {
        PositionInfo memory positionInfo = _getPositionInfo(position);
        LegacyInfo storage legacyInfo = legacyInfos[position];
        require(bidSize > 0 && bidSize <= positionInfo.totalSize, "VaultButler: Invalid bidSize");
        uint256 bidPrice = _priceOfLegacy(positionInfo);
        uint256 usedCash = bidSize.mul(bidPrice).div(10**(positionInfo.stakedTokenDecimals.add(18).sub(positionInfo.stableTokenDecimals)));
        IPool(positionInfo.strToken).takeLegacyStableToken{value: msg.value}(msg.sender, position, usedCash, bidSize);

        legacyInfo.bidSize = legacyInfo.bidSize.add(bidSize);
        legacyInfo.usedCash = legacyInfo.usedCash.add(usedCash);
        if (legacyInfo.bidSize == positionInfo.totalSize) {
            tradingHub.updatePositionState(position, 8);
            IPool(positionInfo.strToken).auctionClosed(position, 0, 0);
        }
        emit ExecuteNaginata(position, msg.sender, bidSize, usedCash);
    }

    function _priceOfLegacy(PositionInfo memory positionInfo) internal view returns (uint256) {
        require(positionInfo.positionState == OVERDRAWN_STATE, "VaultButler: Not a legacy position");
        uint256 currentPrice = priceOracle.getLatestMixinPrice(positionInfo.stakedToken);
        currentPrice = currentPrice.mul(102).div(100);

        uint256 overdrawnPrice = positionInfo.unsettledCash.mul(10**(positionInfo.stakedTokenDecimals.add(18).sub(positionInfo.stableTokenDecimals))).div(positionInfo.totalSize);
        if (currentPrice > overdrawnPrice) {
            return overdrawnPrice;
        }
        return currentPrice;
    }

    function initialize(
        address _shorterBone,
        address _tradingHub,
        address _priceOracle,
        address _committee
    ) external isSavior {
        require(!_initialized, "VaultButler: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        tradingHub = ITradingHub(_tradingHub);
        priceOracle = IPriceOracle(_priceOracle);
        committee = ICommittee(_committee);
        _initialized = true;
    }

    function _getPositionInfo(address position) internal view returns (PositionInfo memory positionInfo) {
        (, address strToken, , uint256 positionState) = tradingHub.getPositionState(position);
        (, address stakedToken, address stableToken, , , , , , , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, ) = IPool(strToken).getMetaInfo();
        (uint256 totalSize, uint256 unsettledCash) = IPool(strToken).getPositionAssetInfo(position);
        positionInfo = PositionInfo({strToken: strToken, stakedToken: stakedToken, stableToken: stableToken, stakedTokenDecimals: stakedTokenDecimals, stableTokenDecimals: stableTokenDecimals, totalSize: totalSize, unsettledCash: unsettledCash, positionState: positionState});
    }
}
