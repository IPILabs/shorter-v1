// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IAuctionHall {
    function inquire()
        external
        view
        returns (
            address[] memory closedPositions,
            address[] memory legacyPositions
        );

    function initAuctionPosition(
        address position,
        address strPool,
        uint256 closingBlock
    ) external;

    // Events
    event AuctionInitiated(address indexed positionAddr);
    event BidTanto(address indexed positionAddr, address indexed ruler, uint256 bidSize, uint256 priorityFee);
    event Phase1Rollback(address indexed positionAddr);
    event BidKatana(address indexed positionAddr, address indexed ruler, uint256 debtSize, uint256 usedCash, uint256 dexCoverReward);
    event AuctionFinished(address indexed positionAddr, uint256 indexed phase);
    event Retrieve(address indexed positionAddr, uint256 stableTokenSize, uint256 debtTokenSize, uint256 priorityFee);
}
