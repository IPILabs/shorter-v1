// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/AllyLibrary.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IPool.sol";
import "../interfaces/v1/model/IInterestRateModel.sol";
import "../criteria/ChainSchema.sol";
import "../storage/PoolStorage.sol";
import "../tokens/ERC20.sol";

contract PoolGarner is ChainSchema, PoolStorage, ERC20 {
    using AllyLibrary for IShorterBone;

    /// @notice Emitted when user increase margin
    event IncreaseMargin(address indexed trader, address indexed position, uint256 amount);

    uint256 public maxCapacity;
    mapping(address => uint256) public positionOpenPriceMap;
    uint256 public feeProtocol;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    modifier onlyPoolGuardian() {
        shorterBone.assertCaller(msg.sender, AllyLibrary.POOL_GUARDIAN);
        _;
    }

    modifier onlyTradingHub() {
        shorterBone.assertCaller(msg.sender, AllyLibrary.TRADING_HUB);
        _;
    }

    function deposit(uint256 amount) external payable whenNotPaused {
        require(_totalSupply.add(amount) <= maxCapacity || maxCapacity == 0, "PoolGarner: Deposit tokens over the maxCapacity");
        require(uint256(endBlock) > block.number && stateFlag == IPoolGuardian.PoolStatus.RUNNING, "PoolGarner: Expired pool");
        _deposit(msg.sender, amount);
        poolRewardModel.harvestByStrToken(id, msg.sender, balanceOf[msg.sender].add(amount));
        _mint(msg.sender, amount);
        poolUserUpdateBlock[msg.sender] = block.number.to64();
        emit Deposit(msg.sender, id, amount);
    }

    function withdraw(uint256 percent, uint256 amount) external whenNotPaused {
        require(tradingHub.isPoolWithdrawable(id), "PoolGarner: Legacy positions found");
        require(stateFlag == IPoolGuardian.PoolStatus.RUNNING || stateFlag == IPoolGuardian.PoolStatus.ENDED, "PoolGarner: Pool is liquidating");
        uint256 withdrawAmount;
        uint256 burnAmount;
        if (isLegacyLeftover) {
            (withdrawAmount, burnAmount) = _tryWithdrawByPercent(percent);
        } else {
            (withdrawAmount, burnAmount) = _tryWithdrawByAmount(amount);
        }

        _withdrawStakedToken(msg.sender, withdrawAmount, burnAmount);

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

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transferWithHarvest(from, to, value);
        return true;
    }

    function initialize(address _wrapRouter, address _tradingHubAddr, address _poolRewardModelAddr, uint256 __blocksPerDay, address _WrappedEtherAddr, IPool.CreatePoolParams calldata _createPoolParams) external onlyPoolGuardian {
        require(_createPoolParams.creator != address(0), "PoolGarner: Creator is zero address");
        require(_tradingHubAddr != address(0), "PoolGarner: TradingHub is zero address");
        stakedToken = ISRC20(_createPoolParams.stakedToken);
        stableToken = ISRC20(_createPoolParams.stableToken);
        wrapRouter = IWrapRouter(_wrapRouter);
        wrappedToken = ISRC20(wrapRouter.inherits(_createPoolParams.stakedToken));
        stakedTokenDecimals = stakedToken.decimals();
        stableTokenDecimals = stableToken.decimals();
        creator = _createPoolParams.creator;
        id = _createPoolParams.poolId;
        leverage = _createPoolParams.leverage.to64();
        durationDays = _createPoolParams.durationDays.to64();
        _name = string(abi.encodePacked("Shorter Pool #", Strings.toString(_createPoolParams.poolId)));
        _symbol = string(abi.encodePacked("str", stakedToken.symbol()));
        _decimals = stakedTokenDecimals;
        tradingHub = ITradingHub(_tradingHubAddr);
        poolRewardModel = IPoolRewardModel(_poolRewardModelAddr);
        _blocksPerDay = __blocksPerDay;
        WrappedEtherAddr = _WrappedEtherAddr;
        maxCapacity = _createPoolParams.maxCapacity;
        feeProtocol = _createPoolParams.feeProtocol;
        stakedToken.approve(address(shorterBone), uint256(0) - 1);
        stakedToken.approve(address(wrapRouter), uint256(0) - 1);
        wrappedToken.approve(address(shorterBone), uint256(0) - 1);
        wrappedToken.approve(address(wrapRouter), uint256(0) - 1);
        if (shorterBone.TetherToken() == _createPoolParams.stableToken) {
            IUSDT(_createPoolParams.stableToken).approve(address(shorterBone), uint256(0) - 1);
        } else {
            stableToken.approve(address(shorterBone), uint256(0) - 1);
        }
    }

    function getMetaInfo()
        external
        view
        returns (address creator_, address stakedToken_, address stableToken_, address wrappedToken_, uint256 leverage_, uint256 durationDays_, uint256 startBlock_, uint256 endBlock_, uint256 id_, uint256 stakedTokenDecimals_, uint256 stableTokenDecimals_, IPoolGuardian.PoolStatus stateFlag_)
    {
        return (creator, address(stakedToken), address(stableToken), address(wrappedToken), uint256(leverage), uint256(durationDays), uint256(startBlock), uint256(endBlock), id, uint256(stakedTokenDecimals), uint256(stableTokenDecimals), stateFlag);
    }

    function getWithdrawableAmountByPercent(address account, uint256 percent) public view returns (uint256 withdrawAmount, uint256 burnAmount, uint256 stableTokenAmount) {
        require(percent > 0 && percent <= 100, "PoolGarner: Invalid withdraw percentage");
        require(stateFlag == IPoolGuardian.PoolStatus.ENDED, "PoolGarner: Pool is not ended");
        address stakedToken_;
        uint256 _userShare;
        (stakedToken_, withdrawAmount, burnAmount, _userShare) = wrapRouter.getUnwrappableAmountByPercent(percent, account, address(stakedToken), balanceOf[account], totalBorrowAmount);
        require(stakedToken_ != address(0), "PoolGarner: Insufficient liquidity");
        stableTokenAmount = stableTokenAmountLeftover.mul(_userShare).mul(percent).div(1e20);
    }

    function _tryWithdrawByPercent(uint256 percent) internal returns (uint256 withdrawAmount, uint256 burnAmount) {
        uint256 stableTokenAmount;
        (withdrawAmount, burnAmount, stableTokenAmount) = getWithdrawableAmountByPercent(msg.sender, percent);
        totalBorrowAmount = totalBorrowAmount.add(withdrawAmount).sub(burnAmount);
        stableTokenAmountLeftover = stableTokenAmountLeftover.sub(stableTokenAmount);
        shorterBone.poolTillOut(id, address(stableToken), msg.sender, stableTokenAmount);
    }

    function _tryWithdrawByAmount(uint256 amount) internal view returns (uint256 withdrawAmount, uint256 burnAmount) {
        require(balanceOf[msg.sender] >= amount && amount > 0, "PoolGarner: Invalid withdraw amount");
        address stakedToken_ = wrapRouter.getUnwrappableAmount(msg.sender, address(stakedToken), amount);
        require(stakedToken_ != address(0), "PoolGarner: Insufficient liquidity");
        withdrawAmount = amount;
        burnAmount = amount;
    }

    function _deposit(address account, uint256 amount) internal {
        address _stakedToken = wrapRouter.wrappable(address(stakedToken), address(this), account, amount, msg.value);
        require(_stakedToken != address(0), "PoolGarner: Invalid stake token");
        if (_stakedToken == WrappedEtherAddr) {
            require(msg.value == amount, "PoolGarner: Invalid ether amount");
            IWETH(WrappedEtherAddr).deposit{value: msg.value}();
        } else {
            shorterBone.poolTillIn(id, _stakedToken, account, amount);
        }
        wrapRouter.wrap(id, address(stakedToken), account, amount, _stakedToken);
    }

    function _withdrawStakedToken(address account, uint256 withdrawAmount, uint256 burnAmount) internal {
        uint256 revenueAmount = stateFlag == IPoolGuardian.PoolStatus.RUNNING && uint256(poolUserUpdateBlock[msg.sender]).add(_blocksPerDay.mul(3)) > block.number ? withdrawAmount.div(1000) : 0;
        address treasury = shorterBone.getModule(AllyLibrary.TREASURY);

        address _stakedToken = wrapRouter.unwrap(id, address(stakedToken), account, withdrawAmount, burnAmount);
        shorterBone.poolTillOut(id, _stakedToken, treasury, revenueAmount);
        withdrawAmount = withdrawAmount.sub(revenueAmount);

        if (_stakedToken == WrappedEtherAddr) {
            IWETH(WrappedEtherAddr).withdraw(withdrawAmount);
            msg.sender.transfer(withdrawAmount);
        } else {
            shorterBone.poolTillOut(id, _stakedToken, account, withdrawAmount);
        }
    }

    function _transferWithHarvest(address from, address to, uint256 value) internal {
        wrapRouter.transferTokenShare(id, from, to, value);
        poolRewardModel.harvestByStrToken(id, from, balanceOf[from].sub(value));
        poolRewardModel.harvestByStrToken(id, to, balanceOf[to].add(value));
        _transfer(from, to, value);
    }
}
