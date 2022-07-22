// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../libraries/AllyLibrary.sol";
import "../interfaces/IWETH.sol";
import "../criteria/ChainSchema.sol";
import "../storage/PoolStorage.sol";
import "../tokens/ERC20.sol";

contract PoolGarner is ChainSchema, PoolStorage, ERC20 {
    using AllyLibrary for IShorterBone;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    modifier reentrantLock(uint256 code) {
        require(userReentrantLocks[code][msg.sender] == 0, "PoolGarner: Reentrant call");
        userReentrantLocks[code][msg.sender] = 1;
        _;
        userReentrantLocks[code][msg.sender] = 0;
    }

    modifier onlyPoolGuardian() {
        require(msg.sender == shorterBone.getPoolGuardian(), "PoolGarner: Caller is not PoolGuardian");
        _;
    }

    function deposit(uint256 amount) external payable whenNotPaused reentrantLock(100) {
        require(uint256(endBlock) > block.number && stateFlag == IPoolGuardian.PoolStatus.RUNNING, "PoolGarner: Expired pool");
        _deposit(msg.sender, amount);
        poolRewardModel.harvestByStrToken(id, msg.sender, balanceOf[msg.sender].add(amount));
        _mint(msg.sender, amount);
        poolUserUpdateBlock[msg.sender] = block.number.to64();
        emit Deposit(msg.sender, id, amount);
    }

    function withdraw(uint256 percent, uint256 amount) external whenNotPaused reentrantLock(101) {
        require(tradingHub.isPoolWithdrawable(id), "PoolGarner: Legacy positions found");
        require(stateFlag == IPoolGuardian.PoolStatus.RUNNING || stateFlag == IPoolGuardian.PoolStatus.ENDED, "PoolGarner: Pool is liquidating");
        uint256 withdrawAmount;
        uint256 burnAmount;
        if (isLegacyLeftover) {
            (withdrawAmount, burnAmount) = _getWithdrawableAmountByLegacy(percent);
        } else {
            (withdrawAmount, burnAmount) = _getWithdrawableAmount(amount);
        }

            _withdraw(msg.sender, withdrawAmount);

        poolRewardModel.harvestByStrToken(id, msg.sender, balanceOf[msg.sender].sub(burnAmount));
        _burn(msg.sender, burnAmount);
        poolUserUpdateBlock[msg.sender] = block.number.to64();
        emit Withdraw(msg.sender, id, burnAmount);
    }

    function list() external onlyPoolGuardian {
        startBlock = block.number.to64();
        endBlock = (block.number.add(_blocksPerDay.mul(uint256(durationDays)))).to64();
        stateFlag = IPoolGuardian.PoolStatus.RUNNING;
    }

    function setStateFlag(IPoolGuardian.PoolStatus newStateFlag) external onlyPoolGuardian {
        stateFlag = newStateFlag;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transferWithHarvest(_msgSender(), to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transferWithHarvest(from, to, value);
        return true;
    }

    function initialize(
        address _creator,
        address _stakedToken,
        address _stableToken,
        address _wrapRouter,
        address _tradingHubAddr,
        address _poolRewardModelAddr,
        uint256 _poolId,
        uint256 _leverage,
        uint256 _durationDays,
        uint256 __blocksPerDay,
        address _WrappedEtherAddr
    ) external onlyPoolGuardian {
        require(_creator != address(0), "PoolGarner: Creator is zero address");
        require(_tradingHubAddr != address(0), "PoolGarner: TradingHub is zero address");
        stakedToken = ISRC20(_stakedToken);
        stableToken = ISRC20(_stableToken);
        wrapRouter = IWrapRouter(_wrapRouter);
        wrappedToken = ISRC20(wrapRouter.getInherit(_stakedToken));
        stakedTokenDecimals = stakedToken.decimals();
        stableTokenDecimals = stableToken.decimals();
        creator = _creator;
        id = _poolId;
        leverage = _leverage.to64();
        durationDays = _durationDays.to64();
        _name = string(abi.encodePacked("Shorter Pool ", stakedToken.name()));
        _symbol = string(abi.encodePacked("str", stakedToken.symbol()));
        _decimals = stakedTokenDecimals;
        tradingHub = ITradingHub(_tradingHubAddr);
        poolRewardModel = IPoolRewardModel(_poolRewardModelAddr);
        _blocksPerDay = __blocksPerDay;
        WrappedEtherAddr = _WrappedEtherAddr;
        stakedToken.approve(address(shorterBone), uint256(0) - 1);
        stakedToken.approve(address(wrapRouter), uint256(0) - 1);
        wrappedToken.approve(address(shorterBone), uint256(0) - 1);
        wrappedToken.approve(address(wrapRouter), uint256(0) - 1);
        if (shorterBone.TetherToken() == _stableToken) {
            IUSDT(_stableToken).approve(address(shorterBone), uint256(0) - 1);
        } else {
            stableToken.approve(address(shorterBone), uint256(0) - 1);
        }
    }

    function getMetaInfo()
        external
        view
        returns (
            address creator_,
            address stakedToken_,
            address stableToken_,
            address wrappedToken_,
            uint256 leverage_,
            uint256 durationDays_,
            uint256 startBlock_,
            uint256 endBlock_,
            uint256 id_,
            uint256 stakedTokenDecimals_,
            uint256 stableTokenDecimals_,
            IPoolGuardian.PoolStatus stateFlag_
        )
    {
        return (creator, address(stakedToken), address(stableToken), address(wrappedToken), uint256(leverage), uint256(durationDays), uint256(startBlock), uint256(endBlock), id, uint256(stakedTokenDecimals), uint256(stableTokenDecimals), stateFlag);
    }

    function _getWithdrawableAmountByLegacy(uint256 percent) internal returns (uint256 withdrawAmount, uint256 burnAmount) {
        require(percent > 0 && percent <= 100, "PoolGarner: Invalid withdraw percentage");
        uint256 _userShare;
        address stakedToken_;
        (stakedToken_, withdrawAmount, burnAmount, _userShare) = wrapRouter.getUnwrapableAmountByPercent(percent, msg.sender, address(stakedToken), balanceOf[msg.sender], totalBorrowAmount);
        require(stakedToken_ != address(0), "PoolGarner: Insufficient liquidity");
        if (_userShare > 0) {
            uint256 usdAmount = stableToken.balanceOf(address(this)).mul(_userShare).mul(percent).div(1e20);
            shorterBone.poolTillOut(id, address(stableToken), msg.sender, usdAmount);
        }
    }

    function _getWithdrawableAmount(uint256 amount) internal view returns (uint256 withdrawAmount, uint256 burnAmount) {
        require(balanceOf[msg.sender] >= amount && amount > 0, "PoolGarner _getWithdrawableAmount: Insufficient balance");
        address stakedToken_ = wrapRouter.getUnwrapableAmount(msg.sender, address(stakedToken), amount);
        require(stakedToken_ != address(0), "PoolGarner: Insufficient liquidity");
        withdrawAmount = amount;
        burnAmount = amount;
    }

    function _deposit(address account, uint256 amount) internal {
        address _stakedToken = wrapRouter.wrapable(address(stakedToken), address(this), account, amount, msg.value);
        require(_stakedToken != address(0), "PoolGarner: Insufficient balance");
        if (_stakedToken == WrappedEtherAddr) {
            require(msg.value == amount, "PoolGarner _deposit: Invalid amount");
            IWETH(WrappedEtherAddr).deposit{value: msg.value}();
        } else {
            shorterBone.poolTillIn(id, _stakedToken, account, amount);
        }
        wrapRouter.wrap(id, address(stakedToken), account, amount, _stakedToken);
    }

    function _withdraw(address account, uint256 withdrawAmount) internal {
        uint256 revenueAmount = stateFlag == IPoolGuardian.PoolStatus.RUNNING && uint256(poolUserUpdateBlock[msg.sender]).add(_blocksPerDay.mul(3)) > block.number ? withdrawAmount.div(1000) : 0;
        address treasury = shorterBone.getModule(AllyLibrary.TREASURY);

        address _stakedToken = wrapRouter.unwrap(id, address(stakedToken), account, withdrawAmount);
        shorterBone.poolTillOut(id, _stakedToken, treasury, revenueAmount);
        withdrawAmount = withdrawAmount.sub(revenueAmount);

        if (_stakedToken == WrappedEtherAddr) {
            IWETH(WrappedEtherAddr).withdraw(withdrawAmount);
            msg.sender.transfer(withdrawAmount);
        } else {
            shorterBone.poolTillOut(id, _stakedToken, account, withdrawAmount);
        }
    }

    function _transferWithHarvest(
        address from,
        address to,
        uint256 value
    ) internal {
        wrapRouter.transferTokenShare(id, from, to, value);
        poolRewardModel.harvestByStrToken(id, from, balanceOf[from].sub(value));
        poolRewardModel.harvestByStrToken(id, to, balanceOf[to].add(value));
        _transfer(from, to, value);
    }
}
