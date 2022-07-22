// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../interfaces/IShorterBone.sol";

library AllyLibrary {
    // Ally contracts
    bytes32 public constant SHORTER_BONE = keccak256("SHORTER_BONE");
    bytes32 public constant SHORTER_FACTORY = keccak256("SHORTER_FACTORY");
    bytes32 public constant AUCTION_HALL = keccak256("AUCTION_HALL");
    bytes32 public constant COMMITTEE = keccak256("COMMITTEE");
    bytes32 public constant POOL_GUARDIAN = keccak256("POOL_GUARDIAN");
    bytes32 public constant TRADING_HUB = keccak256("TRADING_HUB");
    bytes32 public constant DEX_CENTER = keccak256("DEX_CENTER");
    bytes32 public constant PRICE_ORACLE = keccak256("PRICE_ORACLE");
    bytes32 public constant VAULT_BUTLER = keccak256("VAULT_BUTLER");
    bytes32 public constant TREASURY = keccak256("TREASURY");
    bytes32 public constant FARMING = keccak256("FARMING");
    bytes32 public constant IPI_STR = keccak256("IPI_STR");
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

    function getModule(IShorterBone shorterBone, bytes32 moduleId) public view returns (address) {
        return shorterBone.getAddress(moduleId);
    }

    function assertCaller(
        IShorterBone shorterBone,
        address caller,
        bytes32 moduleId
    ) external view {
        address addr = getModule(shorterBone, moduleId);
        require(caller == addr, "AllyCheck: Failed");
    }

    function checkCaller(
        IShorterBone shorterBone,
        address caller,
        bytes32 moduleId
    ) external view returns (bool) {
        address addr = getModule(shorterBone, moduleId);
        return caller == addr;
    }

    function getShorterFactory(IShorterBone shorterBone) external view returns (address) {
        return getModule(shorterBone, SHORTER_FACTORY);
    }

    function getAuctionHall(IShorterBone shorterBone) external view returns (address) {
        return getModule(shorterBone, AUCTION_HALL);
    }

    function getPoolGuardian(IShorterBone shorterBone) external view returns (address) {
        return getModule(shorterBone, POOL_GUARDIAN);
    }

    function getTradingHub(IShorterBone shorterBone) external view returns (address) {
        return getModule(shorterBone, TRADING_HUB);
    }

    function getPriceOracle(IShorterBone shorterBone) external view returns (address) {
        return getModule(shorterBone, PRICE_ORACLE);
    }

    function getGovRewardModel(IShorterBone shorterBone) external view returns (address) {
        return getModule(shorterBone, GOV_REWARD);
    }

    function getInterestRateModel(IShorterBone shorterBone) external view returns (address) {
        return getModule(shorterBone, INTEREST_RATE);
    }
}
