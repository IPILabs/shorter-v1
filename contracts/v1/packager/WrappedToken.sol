// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../util/BoringMath.sol";
import "../../util/Ownable.sol";
import "../../util/Pausable.sol";
import "../../storage/WrappedTokenStorage.sol";

contract WrappedToken is Ownable, Pausable, WrappedTokenStorage {
    using BoringMath for uint256;
    address public immutable wrapRouter;

    modifier onlyWrapRouter() {
        require(msg.sender == wrapRouter, "WrappedToken: Caller is not wrapRouter");
        _;
    }

    constructor(address _wrapRouter) public {
        wrapRouter = _wrapRouter;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 value) public onlyWrapRouter {
        balanceOf[account] = balanceOf[account].add(value);
        _totalSupply = _totalSupply.add(value);
    }

    function burn(address account, uint256 value) public onlyWrapRouter {
        require(balanceOf[account] >= value);
        balanceOf[account] = balanceOf[account].sub(value);
        _totalSupply = _totalSupply.sub(value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function transfer(address to, uint256 value) external whenNotPaused returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external whenNotPaused returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }

        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 decimals_
    ) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = uint8(decimals_);
    }
}
