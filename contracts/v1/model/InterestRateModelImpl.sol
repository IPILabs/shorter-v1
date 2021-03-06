// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../interfaces/v1/model/IInterestRateModel.sol";
import "../../interfaces/IShorterBone.sol";
import "../../interfaces/IStrPool.sol";
import "../../interfaces/v1/IPoolGuardian.sol";
import "../../criteria/ChainSchema.sol";
import "../../storage/model/InterestRateModelStorage.sol";
import "../../util/BoringMath.sol";
import "../Rescuable.sol";

contract InterestRateModelImpl is Rescuable, ChainSchema, Pausable, InterestRateModelStorage, IInterestRateModel {
    using BoringMath for uint256;

    constructor(address _SAVIOR) public Rescuable(_SAVIOR) {}

    function getBorrowRate(uint256 poolId, uint256 userBorrowCash) public view override returns (uint256 fundingFeePerBlock) {
        uint256 _annualized = getBorrowApy(poolId);
        fundingFeePerBlock = userBorrowCash.mul(_annualized).div(uint256(365).mul(blocksPerDay()));
    }

    function getBorrowApy(uint256 poolId) public view returns (uint256 annualized_) {
        (uint256 totalBorrowAmount, uint256 totalStakedAmount) = getPoolInfo(poolId);

        if (totalStakedAmount == 0) {
            return 0;
        }

        uint256 utilization = totalBorrowAmount.mul(1e18).div(totalStakedAmount);

        annualized_ = annualized;
        if (utilization < kink) {
            annualized_ = annualized_.add(utilization.mul(multiplier).div(1e18));
        } else {
            annualized_ = annualized_.add(kink.mul(multiplier).div(1e18));
            annualized_ = annualized_.add((utilization.sub(kink)).mul(jumpMultiplier).div(1e18));
        }
    }

    function getPoolInfo(uint256 _poolId) internal view returns (uint256 totalBorrowAmount_, uint256 totalStakedAmount_) {
        (, address strToken, ) = poolGuardian.getPoolInfo(_poolId);
        (, , , address wrappedToken, , , , , , , , ) = IStrPool(strToken).getInfo();

        totalStakedAmount_ = ISRC20(strToken).totalSupply();
        uint256 reserves = ISRC20(wrappedToken).balanceOf(strToken);

        totalBorrowAmount_ = reserves > totalStakedAmount_ ? 0 : totalStakedAmount_.sub(reserves);
    }

    function setMultiplier(uint256 _multiplier) external isManager {
        multiplier = _multiplier;
    }

    function setJumpMultiplier(uint256 _jumpMultiplier) external isManager {
        jumpMultiplier = _jumpMultiplier;
    }

    function setKink(uint256 _kink) external isManager {
        kink = _kink;
    }

    function setAnnualized(uint256 _annualized) external isManager {
        annualized = _annualized;
    }

    function initialize(address _poolGuardian) public isKeeper {
        require(!_initialized, "InterestRateModel: Already initialized");

        poolGuardian = IPoolGuardian(_poolGuardian);
        multiplier = 125000;
        jumpMultiplier = 2000000;
        kink = 8 * 1e17;
        annualized = 1e5;

        _initialized = true;
    }
}
