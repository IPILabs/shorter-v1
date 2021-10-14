// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./libraries/AllyLibrary.sol";
import "./interfaces/governance/IIpistrToken.sol";
import "./interfaces/ISRC20.sol";
import "./interfaces/IUSDT.sol";
import "./interfaces/IShorterBone.sol";
import "./interfaces/v1/ITradingHub.sol";
import "./criteria/Affinity.sol";
import "./util/BoringMath.sol";

/// @notice Mainstay for system and smart contracts
contract ShorterBone is Affinity, IShorterBone {
    using SafeToken for ISRC20;
    using BoringMath for uint256;

    struct TokenInfo {
        bool inWhiteList;
        address swapRouter;
        uint256 multiplier;
    }

    bool internal mintable;
    bool internal lockedMintable;
    uint256 public totalTokenSize;
    address public override TetherToken;

    /// @notice Ally contract and corresponding verified id
    mapping(bytes32 => address) public allyContracts;
    mapping(address => TokenInfo) public override getTokenInfo;
    mapping(uint256 => address) public tokens;

    constructor(address _SAVIOR) public Affinity(_SAVIOR) {
        mintable = true;
        lockedMintable = true;
    }

    modifier onlyAlly(bytes32 allyId) {
        require(msg.sender == allyContracts[allyId], "ShorterBone: Caller is not an ally");
        _;
    }

    /// @notice Move the token from user to ally contracts, restricted to be called by the ally contract self
    function tillIn(
        address tokenAddr,
        address user,
        bytes32 toAllyId,
        uint256 amount
    ) external override onlyAlly(toAllyId) {
        require(allyContracts[toAllyId] != address(0), "ShorterBone: toAllyId is zero Address");

        _transfer(tokenAddr, user, allyContracts[toAllyId], amount);

        emit TillIn(toAllyId, user, tokenAddr, amount);
    }

    /// @notice Move the token from an ally contract to user, restricted to be called by the ally contract
    function tillOut(
        address tokenAddr,
        bytes32 fromAllyId,
        address user,
        uint256 amount
    ) external override onlyAlly(fromAllyId) {
        require(allyContracts[fromAllyId] != address(0), "ShorterBone: Invalid fromAllyId");

        _transfer(tokenAddr, allyContracts[fromAllyId], user, amount);

        emit TillOut(fromAllyId, user, tokenAddr, amount);
    }

    function poolTillIn(
        uint256 poolId,
        address token,
        address user,
        uint256 amount
    ) external override {
        address strToken = getStrToken(poolId);
        require(msg.sender == strToken, "ShorterBone: Caller is not StrPool");
        _transfer(token, user, strToken, amount);
        emit PoolTillIn(poolId, user, amount);
    }

    function poolTillOut(
        uint256 poolId,
        address token,
        address user,
        uint256 amount
    ) external override {
        address strToken = getStrToken(poolId);
        require(msg.sender == strToken, "ShorterBone: Caller is not StrPool");
        _transfer(token, strToken, user, amount);
        emit PoolTillOut(poolId, user, amount);
    }

    function poolRevenue(
        uint256 poolId,
        address user,
        address token,
        uint256 amount,
        IncomeType _type
    ) external override {
        address strToken = getStrToken(poolId);
        require(msg.sender == strToken, "ShorterBone: Caller is not StrPool");
        _transfer(token, strToken, allyContracts[AllyLibrary.TREASURY], amount);
        emit Revenue(token, user, amount, _type);
    }

    function revenue(
        bytes32 sendAllyId,
        address tokenAddr,
        address from,
        uint256 amount,
        IncomeType _type
    ) external override onlyAlly(sendAllyId) {
        address treasuryAddr = allyContracts[AllyLibrary.TREASURY];

        require(treasuryAddr != address(0), "ShorterBone: Treasury is not ready");

        _transfer(tokenAddr, from, treasuryAddr, amount);

        emit Revenue(tokenAddr, from, amount, _type);
    }

    function getStrToken(uint256 poolId) internal view returns (address strToken) {
        address poolGuardian = allyContracts[AllyLibrary.POOL_GUARDIAN];
        (, strToken, ) = IPoolGuardian(poolGuardian).getPoolInfo(poolId);
    }

    function mintByAlly(
        bytes32 sendAllyId,
        address user,
        uint256 amount
    ) external override onlyAlly(sendAllyId) {
        require(mintable, "ShorterBone: Mint is unavailable for now");

        _mint(user, amount);
    }

    function getAddress(bytes32 allyId) external view override returns (address) {
        address res = allyContracts[allyId];
        require(res != address(0), "ShorterBone: AllyId not found");
        return res;
    }

    function setAlly(bytes32 allyId, address contractAddr) external isKeeper {
        allyContracts[allyId] = contractAddr;

        emit ResetAlly(allyId, contractAddr);
    }

    function slayAlly(bytes32 allyId) external isKeeper {
        delete allyContracts[allyId];

        emit AllyKilled(allyId);
    }

    /// @notice Tweak the mint flag
    function setMintState(bool _flag) external isKeeper {
        mintable = _flag;
    }

    /// @notice Tweak the locked mint flag
    function setLockedMintState(bool _flag) external isKeeper {
        lockedMintable = _flag;
    }

    function addTokenWhiteList(
        address token,
        address swapRouter,
        uint256 multiplier
    ) public isManager {
        _addTokenWhiteList(token, swapRouter, multiplier);
    }

    function batchAddTokenWhiteList(
        address _swapRouter,
        address[] calldata tokenAddrs,
        uint256[] calldata _multipliers
    ) external isManager {
        require(tokenAddrs.length == _multipliers.length, "ShorterBone: Invaild params");
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            _addTokenWhiteList(tokenAddrs[i], _swapRouter, _multipliers[i]);
        }
    }

    function setTokenInWhiteList(address token, bool flag) external isManager {
        getTokenInfo[token].inWhiteList = flag;
    }

    function setSwapRouter(address token, address newSwapRouter) external isManager {
        getTokenInfo[token].swapRouter = newSwapRouter;
    }

    function setMultiplier(address token, uint256 multiplier) external {
        require(msg.sender == allyContracts[AllyLibrary.COMMITTEE], "ShorterBone: Caller is not committee");
        getTokenInfo[token].multiplier = multiplier;
    }

    function mint(address[] calldata users, uint256[] calldata amounts) external isManager {
        require(mintable, "ShorterBone: Mint is unavailable for now");
        require(users.length == amounts.length, "ShorterBone: Invalid mint params");
        for (uint256 i = 0; i < users.length; i++) {
            _mint(users[i], amounts[i]);
        }
    }

    function approve(bytes32 allyId, address tokenAddr) external isManager {
        _approve(allyId, tokenAddr);
    }

    function setTetherToken(address _TetherToken) external isManager {
        TetherToken = _TetherToken;
    }

    function _transfer(
        address tokenAddr,
        address from,
        address to,
        uint256 value
    ) internal {
        ISRC20 token = ISRC20(tokenAddr);
        require(token.allowance(from, address(this)) >= value, "ShorterBone: Amount exceeded the limit");
        uint256 token0Bal = token.balanceOf(from);
        uint256 token1Bal = token.balanceOf(to);

        if (tokenAddr == TetherToken) {
            IUSDT(tokenAddr).transferFrom(from, to, value);
        } else {
            token.safeTransferFrom(from, to, value);
        }

        uint256 token0Aft = token.balanceOf(from);
        uint256 token1Aft = token.balanceOf(to);

        if (token0Aft.add(value) != token0Bal || token1Bal.add(value) != token1Aft) {
            revert("ShorterBone: Fatal exception. transfer failed");
        }
    }

    function _mint(address user, uint256 amount) internal {
        address ipistrAddr = allyContracts[AllyLibrary.IPI_STR];
        require(ipistrAddr != address(0), "ShorterBone: IPISTR unavailable");

        IIpistrToken(ipistrAddr).mint(user, amount);
    }

    function _addTokenWhiteList(
        address token,
        address swapRouter,
        uint256 multiplier
    ) internal {
        tokens[totalTokenSize++] = token;
        getTokenInfo[token] = TokenInfo({inWhiteList: true, swapRouter: swapRouter, multiplier: multiplier});

        _approve(AllyLibrary.AUCTION_HALL, token);
        _approve(AllyLibrary.VAULT_BUTLER, token);
    }

    function _approve(bytes32 allyId, address tokenAddr) internal {
        if (tokenAddr == TetherToken) {
            IAffinity(allyContracts[allyId]).allowTetherToken(tokenAddr, address(this), uint256(0) - 1);
        } else {
            IAffinity(allyContracts[allyId]).allow(tokenAddr, address(this), uint256(0) - 1);
        }
    }
}
