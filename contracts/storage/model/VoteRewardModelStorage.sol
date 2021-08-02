// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../TitanCoreStorage.sol";
import "../../interfaces/governance/ICommittee.sol";

contract VoteRewardModelStorage is TitanCoreStorage {
    bool internal _initialized;

    uint256 public ipistrPerProposal = 1e22;

    address public farming;
    ICommittee public committee;

    // proposalId => (userAddr => isUserWithdrawn); user is withdraw
    mapping(uint256 => mapping(address => bool)) internal isUserWithdraw;
}
