// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

/// @notice Interfaces of StateArcade
interface IStateArcade {
    function fetchPoolUsers(uint256 poolId, uint256 flag) external view returns (address[] memory);

    function notifyUserDepositPool(
        address _account,
        uint256 _poolId,
        uint256 _changeAmount
    ) external;

    function notifyUserWithdrawPool(
        address _account,
        uint256 _poolId,
        uint256 _changeAmount
    ) external;

    function notifyUserBorrowPool(
        address _account,
        uint256 _poolId,
        uint256 _changeAmount
    ) external;

    function notifyUserRepayPool(
        address _account,
        uint256 _poolId,
        uint256 _changeAmount
    ) external;

    function notifyUserTradingFee(
        address positionAddr,
        address account,
        uint256 tradingFee
    ) external;

    function getUsersInSingleRound(uint256 _NoIndex) external view returns (address[] memory _NoUsers);

    function getUserActivePoolIds(address _account) external view returns (uint256[] memory);

    function getTokenTVL(address _tokenAddr) external view returns (uint256 _amount, uint256 _borrowAmount);

    function getUserTradingFee(uint256 _NoIndex, address _account) external view returns (uint256 _userFee);

    function getTotalFeeInfo(uint256 _NoIndex) external view returns (uint256 _totalFee, uint256 _ipistrTokenPrice);

    function getNo1Index() external view returns (uint256 _No1Index);

    function updateLegacyTokenData(
        uint256 poolId,
        uint256 amount,
        address tokenAddr
    ) external;
}
