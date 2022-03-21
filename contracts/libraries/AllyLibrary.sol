// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../interfaces/governance/ICommittee.sol";
import "../interfaces/IShorterBone.sol";
import "../interfaces/IShorterFactory.sol";
import "../interfaces/v1/model/IGovRewardModel.sol";
import "../interfaces/v1/IAuctionHall.sol";
import "../interfaces/v1/IVaultButler.sol";
import "../interfaces/v1/IPoolGuardian.sol";
import "../interfaces/v1/IFarming.sol";
import "../interfaces/v1/ITradingHub.sol";
import "../interfaces/v1/model/IPoolRewardModel.sol";
import "../interfaces/v1/model/IVoteRewardModel.sol";
import "../interfaces/v1/model/IFarmingRewardModel.sol";
import "../interfaces/v1/model/ITradingRewardModel.sol";
import "../interfaces/v1/model/IInterestRateModel.sol";
import "../interfaces/governance/IIpistrToken.sol";
import "../interfaces/IStateArcade.sol";
import "../oracles/IPriceOracle.sol";

library AllyLibrary {
    // Ally contracts
    bytes32 public constant AUCTION_HALL = keccak256("AUCTION_HALL");
    bytes32 public constant COMMITTEE = keccak256("COMMITTEE");
    bytes32 public constant DEX_CENTER = keccak256("DEX_CENTER");
    bytes32 public constant IPI_STR = keccak256("IPI_STR");
    bytes32 public constant PRICE_ORACLE = keccak256("PRICE_ORACLE");
    bytes32 public constant POOL_GUARDIAN = keccak256("POOL_GUARDIAN");
    bytes32 public constant SAVIOR_ADDRESS = keccak256("SAVIOR_ADDRESS");
    bytes32 public constant TRADING_HUB = keccak256("TRADING_HUB");
    bytes32 public constant VAULT_BUTLER = keccak256("VAULT_BUTLER");
    bytes32 public constant TREASURY = keccak256("TREASURY");
    bytes32 public constant SHORTER_FACTORY = keccak256("SHORTER_FACTORY");
    bytes32 public constant FARMING = keccak256("FARMING");
    bytes32 public constant POSITION_OPERATOR = keccak256("POSITION_OPERATOR");
    bytes32 public constant STR_TOKEN_IMPL = keccak256("STR_TOKEN_IMPL");
    bytes32 public constant SHORTER_BONE = keccak256("SHORTER_BONE");
    bytes32 public constant BRIDGANT = keccak256("BRIDGANT");
    bytes32 public constant TRANCHE_ALLOCATOR = keccak256("TRANCHE_ALLOCATOR");

    // Models
    bytes32 public constant FARMING_REWARD = keccak256("FARMING_REWARD");
    bytes32 public constant POOL_REWARD = keccak256("POOL_REWARD");
    bytes32 public constant VOTE_REWARD = keccak256("VOTE_REWARD");
    bytes32 public constant GOV_REWARD = keccak256("GOV_REWARD");
    bytes32 public constant TRADING_REWARD = keccak256("TRADING_REWARD");
    bytes32 public constant GRAB_REWARD = keccak256("GRAB_REWARD");
    bytes32 public constant INTEREST_RATE = keccak256("INTEREST_RATE");

    function getShorterFactory(IShorterBone shorterBone) internal view returns (IShorterFactory shorterFactory) {
        shorterFactory = IShorterFactory(shorterBone.getAddress(SHORTER_FACTORY));
    }

    function getAuctionHall(IShorterBone shorterBone) internal view returns (IAuctionHall auctionHall) {
        auctionHall = IAuctionHall(shorterBone.getAddress(AUCTION_HALL));
    }

    function getPoolGuardian(IShorterBone shorterBone) internal view returns (IPoolGuardian poolGuardian) {
        poolGuardian = IPoolGuardian(shorterBone.getAddress(POOL_GUARDIAN));
    }

    function getPriceOracle(IShorterBone shorterBone) internal view returns (IPriceOracle priceOracle) {
        priceOracle = IPriceOracle(shorterBone.getAddress(PRICE_ORACLE));
    }

    function getGovRewardModel(IShorterBone shorterBone) internal view returns (IGovRewardModel govRewardModel) {
        govRewardModel = IGovRewardModel(shorterBone.getAddress(GOV_REWARD));
    }

    function getTradingHub(IShorterBone shorterBone) internal view returns (ITradingHub tradingHub) {
        tradingHub = ITradingHub(shorterBone.getAddress(TRADING_HUB));
    }

    function getInterestRateModel(IShorterBone shorterBone) internal view returns (IInterestRateModel interestRateModel) {
        interestRateModel = IInterestRateModel(shorterBone.getAddress(INTEREST_RATE));
    }
}
