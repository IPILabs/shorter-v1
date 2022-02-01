// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../util/BoringMath.sol";
import "../../util/Ownable.sol";
import "../../util/Pausable.sol";

contract WrapRouter is Ownable, Pausable {
    using BoringMath for uint256;

    mapping(address => address) public getGrandetie;
    mapping(address => address) public getInherit;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));

    function wrap(address stakedToken, uint256 amount) external whenNotPaused {
        require(getGrandetie[stakedToken] != address(0), "WrapRouter: Treasury is zero Address");
        _safeTransferFrom(stakedToken, msg.sender, getGrandetie[stakedToken], amount);
        IWrappedToken(getInherit[stakedToken]).mint(msg.sender, amount);
    }

    function unwrap(address stakedToken, uint256 amount) external whenNotPaused {
        IWrappedToken(getInherit[stakedToken]).burn(msg.sender, amount);
        _safeTransferFrom(stakedToken, getGrandetie[stakedToken], msg.sender, amount);
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

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 token0Bal = IERC20(token).balanceOf(from);
        uint256 token1Bal = IERC20(token).balanceOf(to);
        (bool success, ) = token.call(abi.encodeWithSelector(SELECTOR, from, to, amount));
        require(success, "WrapRouter: TRANSFER_FAILED");
        uint256 token0Aft = IERC20(token).balanceOf(from);
        uint256 token1Aft = IERC20(token).balanceOf(to);
        if (token0Aft.add(amount) != token0Bal || token1Bal.add(amount) != token1Aft) {
            revert("WrapRouter: Fatal exception. transfer failed");
        }
    }
}

interface IWrappedToken {
    function mint(address to, uint256 amount) external;

    function burn(address user, uint256 amount) external;
}
