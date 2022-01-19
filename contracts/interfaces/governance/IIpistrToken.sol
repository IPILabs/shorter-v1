// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

interface IIpistrToken {
    function mint(address to, uint256 amount) external;

    function setLocked(address user, uint256 amount) external;

    function spendableBalanceOf(address account) external view returns (uint256);

    function lockedBalanceOf(address account) external view returns (uint256);

    function unlockBalance(address account, uint256 amount) external;

    event Unlock(address indexed staker, uint256 claimedAmount);
    event Burn(address indexed blackHoleAddr, uint256 burnAmount);
    event Mint(address indexed account, uint256 mintAmount);
    event SetLocked(address user, uint256 amount);
}
