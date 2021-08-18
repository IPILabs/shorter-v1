// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/OracleLibrary.sol";
import "../libraries/AllyLibrary.sol";
import "../interfaces/v1/IVaultButler.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/IShorterBone.sol";
import "../interfaces/IStrPool.sol";
import "../criteria/ChainSchema.sol";
import "../storage/GaiaStorage.sol";
import "../util/BoringMath.sol";
import "./Rescuable.sol";

/// @notice Butler serves the vaults
contract VaultButlerImplV1 is Rescuable, ChainSchema, Pausable, GaiaStorage, IVaultButler {
    using BoringMath for uint256;

    modifier onlyRuler(address ruler) {
        require(committee.isRuler(ruler), "VaultButler: Caller is not ruler");
        _;
    }

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function priceOfLegacy(address position) public view returns (uint256) {
        PositionInfo memory positionInfo = getPositionInfo(position);
        return _priceOfLegacy(positionInfo);
    }

    function executeNaginata(address position, uint256 bidSize) external whenNotPaused onlyRuler(msg.sender) {
        PositionInfo memory positionInfo = getPositionInfo(position);
        LegacyInfo storage legacyInfo = legacyInfos[position];
        require(bidSize > 0 && bidSize <= positionInfo.totalSize.sub(legacyInfo.bidSize), "VaultButler: Invalid bidSize");
        uint256 bidPrice = _priceOfLegacy(positionInfo);
        uint256 usedCash = bidSize.mul(bidPrice).div(10**(positionInfo.stakedTokenDecimals.add(18).sub(positionInfo.stableTokenDecimals)));

        shorterBone.tillIn(positionInfo.stakedToken, msg.sender, AllyLibrary.VAULT_BUTLER, bidSize);
        IStrPool(positionInfo.strToken).stableTillOut(msg.sender, usedCash);
        legacyInfo.bidSize = legacyInfo.bidSize.add(bidSize);
        legacyInfo.usedCash = legacyInfo.usedCash.add(usedCash);

        if (legacyInfo.bidSize == positionInfo.totalSize) {
            shorterBone.tillOut(positionInfo.stakedToken, AllyLibrary.VAULT_BUTLER, positionInfo.strToken, positionInfo.totalSize);
            tradingHub.updatePositionState(position, ITradingHub.PositionState.CLOSED);
            IStrPool(positionInfo.strToken).auctionClosed(position, 0, 0, legacyInfo.usedCash);
        }

        emit ExecuteNaginata(position, msg.sender, bidSize, usedCash);
    }

    function _priceOfLegacy(PositionInfo memory positionInfo) internal view returns (uint256) {
        require(positionInfo.positionState == ITradingHub.PositionState.OVERDRAWN, "VaultButler: Not a legacy position");

        (uint256 currentPrice, uint256 decimals) = priceOracle.getLatestMixinPrice(positionInfo.stakedToken);
        currentPrice = currentPrice.mul(10**(uint256(18).sub(decimals))).mul(102).div(100);

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
    ) public isKeeper {
        require(!_initialized, "VaultButler: Already initialized");
        shorterBone = IShorterBone(_shorterBone);
        tradingHub = ITradingHub(_tradingHub);
        priceOracle = IPriceOracle(_priceOracle);
        committee = ICommittee(_committee);
        _initialized = true;
    }

    function getPositionInfo(address position) internal view returns (PositionInfo memory positionInfo) {
        (, address strToken, , ITradingHub.PositionState positionState) = tradingHub.getPositionInfo(position);
        (, address stakedToken, address stableToken, , , , , , , uint256 stakedTokenDecimals, uint256 stableTokenDecimals, ) = IStrPool(strToken).getInfo();
        (uint256 totalSize, uint256 unsettledCash) = IStrPool(strToken).getPositionInfo(position);
        positionInfo = PositionInfo({strToken: strToken, stakedToken: stakedToken, stableToken: stableToken, stakedTokenDecimals: stakedTokenDecimals, stableTokenDecimals: stableTokenDecimals, totalSize: totalSize, unsettledCash: unsettledCash, positionState: positionState});
    }
}
