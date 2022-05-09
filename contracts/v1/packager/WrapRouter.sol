// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/v1/IPoolGuardian.sol";
import "../../util/BoringMath.sol";
import "../../util/Ownable.sol";
import "../../util/Pausable.sol";

contract WrapRouter is Ownable, Pausable {
    using BoringMath for uint256;

    address public immutable poolGuardian;
    address public immutable wrappedEtherAddr;
    mapping(address => uint256) public controvertibleAmounts;
    mapping(address => mapping(address => uint256)) public transferableAmounts;
    mapping(address => address) public getGrandetie;
    mapping(address => address) public getInherit;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));

    modifier onlyStrPool(uint256 _poolId) {
        (, address strPool, IPoolGuardian.PoolStatus stateFlag) = IPoolGuardian(poolGuardian).getPoolInfo(_poolId);
        require(stateFlag != IPoolGuardian.PoolStatus.GENESIS, "WrapRouter: Invalid status");
        require(strPool == msg.sender, "WrapRouter: Caller is not strPool");
        _;
    }

    constructor(address _poolGuardian, address _wrappedEtherAddr) public {
        poolGuardian = _poolGuardian;
        wrappedEtherAddr = _wrappedEtherAddr;
    }

    function wrap(
        uint256 poolId,
        address token,
        address account,
        uint256 amount,
        address _stakedToken
    ) external whenNotPaused onlyStrPool(poolId) {
        if (token != address(_stakedToken)) return;
        if (msg.sender != account) {
            transferableAmounts[account][msg.sender] = transferableAmounts[account][msg.sender].add(amount);
        }
        controvertibleAmounts[msg.sender] = controvertibleAmounts[msg.sender].add(amount);
        _safeTransferFrom(token, msg.sender, getGrandetie[token], amount);
        IWrappedToken(getInherit[token]).mint(msg.sender, amount);
    }

    function unwrap(
        uint256 poolId,
        address token,
        address account,
        uint256 amount
    ) external whenNotPaused onlyStrPool(poolId) returns (address stakedToken) {
        if (msg.sender == account) {
            require(amount > controvertibleAmounts[msg.sender], "WrapRouter unwrap: Insufficient liquidity");
        } else {
            uint256 stakedBal = transferableAmounts[account][msg.sender];
            if (stakedBal < amount) {
                return getInherit[token];
            }
            transferableAmounts[account][msg.sender] = stakedBal.sub(amount);
        }

        controvertibleAmounts[msg.sender] = controvertibleAmounts[msg.sender].sub(amount);
        IWrappedToken(getInherit[token]).burn(msg.sender, amount);
        _safeTransferFrom(token, getGrandetie[token], msg.sender, amount);
        stakedToken = token;
    }

    function transferTokenShare(
        uint256 poolId,
        address from,
        address to,
        uint256 amount
    ) external onlyStrPool(poolId) {
        require(transferableAmounts[from][msg.sender] >= amount, "WrapRouter transferTokenShare: Insufficient balance");
        transferableAmounts[from][msg.sender] = transferableAmounts[from][msg.sender].sub(amount);
        transferableAmounts[to][msg.sender] = transferableAmounts[to][msg.sender].add(amount);
    }

    function setGrandeties(address[] calldata _tokens, address[] calldata _grandetie) external onlyOwner {
        require(_tokens.length == _grandetie.length, "WrapRouter: Invaild params");

        for (uint256 i = 0; i < _tokens.length; i++) {
            getGrandetie[_tokens[i]] = _grandetie[i];
        }
    }

    function setWrappedTokens(address[] calldata _tokens, address[] calldata _wrappedTokens) external onlyOwner {
        require(_tokens.length == _wrappedTokens.length, "WrapRouter: Invaild params");

        for (uint256 i = 0; i < _tokens.length; i++) {
            getInherit[_tokens[i]] = _wrappedTokens[i];
        }
    }

    function getTransferableAmount(address account, address strPool) public view returns (uint256 amount) {
        return transferableAmounts[account][strPool];
    }

    function wrapable(
        address token,
        address strPool,
        address account,
        uint256 amount,
        uint256 value
    ) public view returns (address stakedToken) {
        if (token == wrappedEtherAddr && getGrandetie[token] != address(0)) {
            stakedToken = _wrapableWithETH(strPool, account, value);
        }
        if (token != wrappedEtherAddr && getGrandetie[token] != address(0)) {
            stakedToken = _wrapableWithToken(token, strPool, account, amount);
        }
    }

    function getUnwrapableAmount(
        address account,
        address token,
        uint256 amount
    ) external view returns (address) {
        uint256 transferableAmount = transferableAmounts[account][msg.sender];
        uint256 controvertibleAmount = controvertibleAmounts[msg.sender];
        if (transferableAmount < amount) {
            return getInherit[token];
        }
        return controvertibleAmount < amount ? address(0) : token;
    }

    function getUnwrapableAmountByPercent(
        uint256 percent,
        address account,
        address token,
        uint256 amount,
        uint256 totalBorrowAmount
    )
        external
        view
        returns (
            address stakedToken,
            uint256 withdrawAmount,
            uint256 burnAmount,
            uint256 userShare
        )
    {
        uint256 transferableAmount = transferableAmounts[account][msg.sender];
        uint256 controvertibleAmount = controvertibleAmounts[msg.sender];
        uint256 _totalStakedTokenAmount = controvertibleAmount.add(totalBorrowAmount);

        userShare = transferableAmount.mul(1e18).div(_totalStakedTokenAmount);

        if (transferableAmount > 0) {
            stakedToken = token;
            withdrawAmount = controvertibleAmount.mul(userShare).mul(percent).div(1e20);
            burnAmount = transferableAmount.mul(percent).div(100);
        } else {
            stakedToken = getInherit[token];
            withdrawAmount = amount.mul(percent).div(100);
            burnAmount = withdrawAmount;
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 token0Bal = IERC20(token).balanceOf(from);
        uint256 token1Bal = IERC20(token).balanceOf(to);
        (bool success, ) = token.call(abi.encodeWithSelector(SELECTOR, from, to, amount));
        require(success, "WrapRouter: Transfer failed");
        uint256 token0Aft = IERC20(token).balanceOf(from);
        uint256 token1Aft = IERC20(token).balanceOf(to);
        if (token0Aft.add(amount) != token0Bal || token1Bal.add(amount) != token1Aft) {
            revert("WrapRouter: Balances check failed");
        }
    }

    function _wrapableWithToken(
        address token,
        address strPool,
        address account,
        uint256 amount
    ) internal view returns (address) {
        uint256 balance0 = IERC20(token).balanceOf(account);
        if (balance0 > amount) {
            return token;
        }
        uint256 balance1 = IERC20(getGrandetie[token]).balanceOf(account);
        if (balance1 > amount && strPool != account) {
            return getGrandetie[token];
        }
    }

    function _wrapableWithETH(
        address strPool,
        address account,
        uint256 value
    ) internal view returns (address) {
        uint256 balance0 = account.balance;
        if (balance0 > value) {
            return wrappedEtherAddr;
        }
        uint256 balance1 = IERC20(getGrandetie[wrappedEtherAddr]).balanceOf(account);
        if (balance1 > value && strPool != account) {
            return getGrandetie[wrappedEtherAddr];
        }
    }
}

interface IWrappedToken {
    function mint(address to, uint256 amount) external;

    function burn(address user, uint256 amount) external;
}
