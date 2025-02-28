// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICERC20} from "../external/ICERC20.sol";

/// @notice Get up to date cToken data without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibCompound {
    using FixedPointMathLib for uint256;

    function viewUnderlyingBalanceOf(ICERC20 cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).mulWadDown(viewExchangeRate(cToken));
    }

    function viewExchangeRate(ICERC20 cToken) internal view returns (uint256) {
        uint256 accrualBlockTimestampPrior = cToken.accrualBlockTimestamp();

        if (accrualBlockTimestampPrior == block.timestamp) {
            return cToken.exchangeRateStored();
        }

        uint256 totalCash = cToken.underlying().balanceOf(address(cToken));
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();

        uint256 borrowRateMantissa = cToken.interestRateModel().getBorrowRate(totalCash, borrowsPrior, reservesPrior);

        require(borrowRateMantissa <= 0.0005e16, "RATE_TOO_HIGH"); // Same as borrowRateMaxMantissa in CTokenInterfaces.sol

        uint256 interestAccumulated =
            (borrowRateMantissa * (block.timestamp - accrualBlockTimestampPrior)).mulWadDown(borrowsPrior);

        uint256 totalReserves = cToken.reserveFactorMantissa().mulWadDown(interestAccumulated) + reservesPrior;
        uint256 totalBorrows = interestAccumulated + borrowsPrior;
        uint256 totalSupply = cToken.totalSupply();

        return totalSupply == 0
            ? cToken.initialExchangeRateMantissa()
            : (totalCash + totalBorrows - totalReserves).divWadDown(totalSupply);
    }
}
