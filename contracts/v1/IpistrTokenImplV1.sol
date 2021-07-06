// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/governance/IIpistrToken.sol";
import "../criteria/ChainSchema.sol";
import "../storage/PrometheusStorage.sol";
import "../tokens/ERC20.sol";
import "./Rescuable.sol";

/// @notice Governance token of Shorter
contract IpistrTokenImplV1 is Rescuable, ChainSchema, Pausable, ERC20, PrometheusStorage, IIpistrToken {
    using BoringMath for uint256;

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function spendableBalanceOf(address account) external view override returns (uint256 _balanceOf) {
        _balanceOf = _spendableBalanceOf(account);
    }

    function lockedBalanceOf(address account) external view override returns (uint256) {
        return _lockedBalances[account];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        require(_spendableBalanceOf(_msgSender()) >= value, "IPISTR: Insufficient spendable amount");
        _transfer(_msgSender(), to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        require(_spendableBalanceOf(from) >= value, "IPISTR: Insufficient spendable amount");

        if (allowance[from][_msgSender()] != uint256(-1)) {
            allowance[from][_msgSender()] = allowance[from][_msgSender()].sub(value);
        }

        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 amount) external override isManager {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    function setLocked(address user, uint256 amount) external override isManager {
        _lockedBalances[user] = _lockedBalances[user].add(amount);
        emit SetLocked(user, amount);
    }

    function unlockBalance(address account, uint256 amount) external override isManager {
        require(_lockedBalances[account] >= amount, "IPISTR: Insufficient lockedBalances");
        _lockedBalances[account] = _lockedBalances[account].sub(amount);
        emit Unlock(account, amount);
    }

    function burn(address account, uint256 amount) external isManager {
        _burn(account, amount);
        emit Burn(account, amount);
    }

    function initialize() public isKeeper {
        _name = "IPI Shorter";
        _symbol = "IPISTR";
        _decimals = 18;
    }

    function _spendableBalanceOf(address account) internal view returns (uint256) {
        return balanceOf[account].sub(_lockedBalances[account]);
    }
}
