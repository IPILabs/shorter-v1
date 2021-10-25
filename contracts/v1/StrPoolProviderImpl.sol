// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/AllyLibrary.sol";
import "../criteria/Affinity.sol";
import "../storage/StrPoolStorage.sol";
import "../tokens/ERC20.sol";

contract StrPoolProviderImpl is Affinity, Pausable, StrPoolStorage, ERC20 {
    constructor(address _SAVIOR) public Affinity(_SAVIOR) {}

    modifier onlyPoolGuardian() {
        require(msg.sender == shorterBone.getAddress(AllyLibrary.POOL_GUARDIAN), "StrPool: Caller is not PoolGuardian");
        _;
    }

    function deposit(uint256 amount) external whenNotPaused {
        require(uint256(endBlock) > block.number && stateFlag == IPoolGuardian.PoolStatus.RUNNING, "StrPool: Expired pool");
        _deposit(msg.sender, amount);
        poolRewardModel.harvestByStrToken(id, msg.sender, balanceOf[msg.sender].add(amount));
        _mint(msg.sender, amount);
        poolUserUpdateBlock[msg.sender] = block.number.to64();
        emit Deposit(msg.sender, id, amount);
    }

    function withdraw(uint256 percent, uint256 amount) external whenNotPaused {
        require(ITradingHub(tradingHub).isPoolWithdrawable(id), "StrPool: Legacy positions found");
        require(stateFlag == IPoolGuardian.PoolStatus.RUNNING || stateFlag == IPoolGuardian.PoolStatus.ENDED, "StrPool: Pool is liquidating");
        (uint256 withdrawAmount, uint256 burnAmount) = getWithdrawAmount(percent, amount);
        if (stateFlag == IPoolGuardian.PoolStatus.RUNNING && durationDays > 3 && uint256(poolUserUpdateBlock[msg.sender]).add(_blocksPerDay.mul(3)) > block.number) {
            _withdraw(msg.sender, withdrawAmount, burnAmount, true);
        } else {
            _withdraw(msg.sender, withdrawAmount, burnAmount, false);
        }
        poolRewardModel.harvestByStrToken(id, msg.sender, balanceOf[msg.sender].sub(burnAmount));
        _burn(msg.sender, burnAmount);
        poolUserUpdateBlock[msg.sender] = block.number.to64();
        emit Withdraw(msg.sender, id, burnAmount);
    }

    function listPool(uint256 __blocksPerDay) external onlyPoolGuardian {
        startBlock = block.number.to64();
        endBlock = (block.number.add(__blocksPerDay.mul(uint256(durationDays)))).to64();
        stateFlag = IPoolGuardian.PoolStatus.RUNNING;
        _blocksPerDay = __blocksPerDay;
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
        address _tradingHub,
        address _poolRewardModel,
        uint256 _poolId,
        uint256 _leverage,
        uint256 _durationDays
    ) external onlyPoolGuardian {
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
        tradingHub = _tradingHub;
        poolRewardModel = IPoolRewardModel(_poolRewardModel);
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

    function getInfo()
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

    function getWithdrawAmount(uint256 percent, uint256 amount) internal returns (uint256 withdrawAmount, uint256 burnAmount) {
        if (isDelivery) {
            require(percent > 0 && amount <= 100, "StrPool: Invalid withdraw percentage");
            if (userStakedTokenAmount[msg.sender] > 0) {
                uint256 _totalStakedTokenAmount = _totalSupply.sub(totalWrappedTokenAmount);
                uint256 userShare = userStakedTokenAmount[msg.sender].mul(1e18).div(_totalStakedTokenAmount);
                withdrawAmount = totalStakedTokenAmount.mul(userShare).mul(percent).div(1e20);
                uint256 usdAmount = stableToken.balanceOf(address(this)).mul(userShare).mul(percent).div(1e20);
                shorterBone.poolTillOut(id, address(stableToken), msg.sender, usdAmount);
                burnAmount = userStakedTokenAmount[msg.sender].mul(userShare).mul(percent).div(1e20);
            } else if (userWrappedTokenAmount[msg.sender] > 0) {
                uint256 userShare = userWrappedTokenAmount[msg.sender].mul(1e18).div(totalWrappedTokenAmount);
                withdrawAmount = totalWrappedTokenAmount.mul(userShare).mul(percent).div(1e20);
                burnAmount = userWrappedTokenAmount[msg.sender].mul(userShare).mul(percent).div(1e20);
            } else {
                revert("StrPool: Insufficient balance");
            }
        } else {
            require(balanceOf[msg.sender] >= amount && amount > 0, "StrPool: Insufficient balance");
            if (userStakedTokenAmount[msg.sender] > 0) {
                require(totalStakedTokenAmount >= amount, "StrPool: Insufficient liquidity");
            } else {
                require(totalWrappedTokenAmount >= amount, "StrPool: Insufficient liquidity");
            }
            withdrawAmount = amount;
            burnAmount = amount;
        }
    }

    function _deposit(address account, uint256 amount) internal {
        if (stakedToken.balanceOf(account) >= amount) {
            shorterBone.poolTillIn(id, address(stakedToken), account, amount);
            IWrapRouter(wrapRouter).wrap(address(stakedToken), amount);
            totalStakedTokenAmount = totalStakedTokenAmount.add(amount);
            userStakedTokenAmount[account] = userStakedTokenAmount[account].add(amount);
        } else if (wrappedToken.balanceOf(account) >= amount) {
            shorterBone.poolTillIn(id, address(wrappedToken), account, amount);
            totalWrappedTokenAmount = totalWrappedTokenAmount.add(amount);
            userWrappedTokenAmount[account] = userWrappedTokenAmount[account].add(amount);
        } else {
            revert("StrPool: Insufficient balance");
        }
    }

    function _withdraw(
        address account,
        uint256 withdrawAmount,
        uint256 burnAmount,
        bool hasWithdrawFee
    ) internal {
        if (userStakedTokenAmount[account] >= burnAmount) {
            IWrapRouter(wrapRouter).unwrap(address(stakedToken), withdrawAmount);
            if (hasWithdrawFee) {
                address treasury = shorterBone.getAddress(AllyLibrary.TREASURY);
                uint256 revenueAmount = withdrawAmount.div(1000);
                shorterBone.poolTillOut(id, address(stakedToken), treasury, revenueAmount);
                shorterBone.poolTillOut(id, address(stakedToken), account, withdrawAmount.sub(revenueAmount));
            } else {
                shorterBone.poolTillOut(id, address(stakedToken), account, withdrawAmount);
            }
            totalStakedTokenAmount = totalStakedTokenAmount.sub(withdrawAmount);
            userStakedTokenAmount[account] = userStakedTokenAmount[account].sub(burnAmount);
        } else if (userWrappedTokenAmount[account] >= burnAmount) {
            if (hasWithdrawFee) {
                address treasury = shorterBone.getAddress(AllyLibrary.TREASURY);
                uint256 revenueAmount = withdrawAmount.div(1000);
                shorterBone.poolTillOut(id, address(wrappedToken), treasury, revenueAmount);
                shorterBone.poolTillOut(id, address(wrappedToken), account, withdrawAmount.sub(revenueAmount));
            } else {
                shorterBone.poolTillOut(id, address(wrappedToken), account, withdrawAmount);
            }
            totalWrappedTokenAmount = totalWrappedTokenAmount.sub(withdrawAmount);
            userWrappedTokenAmount[account] = userWrappedTokenAmount[account].sub(burnAmount);
        } else {
            revert("StrPool: Insufficient balance");
        }
    }

    function _transferWithHarvest(
        address from,
        address to,
        uint256 value
    ) internal {
        if (userStakedTokenAmount[from] > value) {
            userStakedTokenAmount[from] = userStakedTokenAmount[from].sub(value);
            userStakedTokenAmount[to] = userStakedTokenAmount[to].add(value);
        } else if (userWrappedTokenAmount[msg.sender] > value) {
            userWrappedTokenAmount[from] = userWrappedTokenAmount[from].sub(value);
            userWrappedTokenAmount[to] = userWrappedTokenAmount[to].add(value);
        } else {
            revert("StrPool: Insufficient balance");
        }
        poolRewardModel.harvestByStrToken(id, from, balanceOf[from].sub(value));
        poolRewardModel.harvestByStrToken(id, to, balanceOf[to].add(value));
        _transfer(from, to, value);
    }
}
