pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Calculate} from "contracts/libraries/Calculate.sol";
import {Estimator} from "contracts/Estimator.sol";

// @openzeppelin/test/utils/math/Math.t.sol
function _mulHighLow(
    uint256 x,
    uint256 y
) pure returns (uint256 high, uint256 low) {
    (uint256 x0, uint256 x1) = (x & type(uint128).max, x >> 128);
    (uint256 y0, uint256 y1) = (y & type(uint128).max, y >> 128);

    // Karatsuba algorithm
    // https://en.wikipedia.org/wiki/Karatsuba_algorithm
    uint256 z2 = x1 * y1;
    uint256 z1a = x1 * y0;
    uint256 z1b = x0 * y1;
    uint256 z0 = x0 * y0;

    uint256 carry = ((z1a & type(uint128).max) +
        (z1b & type(uint128).max) +
        (z0 >> 128)) >> 128;

    high = z2 + (z1a >> 128) + (z1b >> 128) + carry;

    unchecked {
        low = x * y;
    }
}

function mulDivValid(uint256 x, uint256 y, uint256 z) pure returns (bool) {
    // Full precision for x * y
    (uint256 xyHi, ) = _mulHighLow(x, y);

    // Assume result won't overflow
    // This also checks that `d` is positive
    return xyHi < z;
}

function mulValid(uint256 x, uint256 y) pure returns (bool) {
    if (x == 0 || y == 0) return true;

    return type(uint256).max / x > y && type(uint256).max / y > x;
}

function addValid(uint256 x, uint256 y) pure returns (bool) {
    return type(uint256).max - x > y && type(uint256).max - y > x;
}

function assume_removeLiquidity(
    uint256 reserveBaseInvariant,
    uint256 minimumBase,
    uint256 availableLiquidity,
    uint256 totalSupply,
    function(bool) external assume
) {
    assume(mulDivValid(totalSupply, minimumBase, reserveBaseInvariant));

    uint256 minimumLiquidityExpected = Math.mulDiv(
        totalSupply,
        minimumBase,
        reserveBaseInvariant
    );

    // no "removeLiquidity: INSUFFICIENT_LIQUIDITY"
    assume(availableLiquidity >= minimumLiquidityExpected);
}

function assume_swapToRatio(
    uint256 reserveBase,
    uint256 reserveQuote,
    uint256 targetBase,
    uint256 targetQuote,
    uint256 feeNumerator,
    uint256 feeDenominator,
    function(bool) external assume
) {
    // reserves are full enough for precise division
    assume(reserveBase > 100 && reserveQuote > 100);

    // target parts are larger than 0
    assume(targetBase > 0 && targetQuote > 0);

    // reserveBaseDesired won't fail
    assume(mulValid(targetBase, 1000));
    assume(mulDivValid(targetBase * 1000, reserveQuote, targetQuote));

    uint256 reserveBaseDesired = Math.mulDiv(
        targetBase * 1000,
        reserveQuote,
        targetQuote
    );

    assume(mulValid(reserveBase, 1000));
    bool baseToQuote = reserveBaseDesired > reserveBase * 1000;

    // invariant, K won't fail
    assume(mulValid(reserveBase, reserveQuote));

    // reserveInOptimal won't fail
    uint256 invariant = reserveBase * reserveQuote;

    assume(mulDivValid(invariant, targetBase, targetQuote));
    assume(mulDivValid(invariant, targetQuote, targetBase));

    uint256 reserveInOptimal = Math.sqrt(
        Math.mulDiv(
            invariant, // invariant, K
            baseToQuote ? targetBase : targetQuote,
            baseToQuote ? targetQuote : targetBase
        )
    );

    (uint256 reserveIn, uint256 reserveOut) = baseToQuote
        ? (reserveBase, reserveQuote)
        : (reserveQuote, reserveBase);

    assume_getAmountOut(
        reserveInOptimal - reserveIn,
        reserveIn,
        reserveOut,
        feeNumerator,
        feeDenominator,
        assume
    );
}

function assume_addLiquidity(
    uint256 reserveBase,
    uint256 reserveQuote,
    uint256 reserveBaseInvariant,
    function(bool) external assume
) {
    assume(reserveBaseInvariant >= reserveBase);

    assume(
        mulDivValid(
            reserveBaseInvariant - reserveBase,
            reserveQuote,
            reserveBase
        )
    );
}

function assume_checkPrecision(
    uint256 reserveBase,
    uint256 reserveQuote,
    uint256 targetBase,
    uint256 targetQuote,
    uint256 precisionNumerator,
    uint256 precisionDenominator,
    function(bool) external assume
) {
    (
        uint256 reserveA,
        uint256 reserveB,
        uint256 targetA,
        uint256 targetB
    ) = reserveBase > reserveQuote
            ? (reserveBase, reserveQuote, targetBase, targetQuote)
            : (reserveQuote, reserveBase, targetQuote, targetBase);

    assume(mulDivValid(reserveA, precisionDenominator, reserveB));

    assume(mulDivValid(targetA, precisionDenominator, targetB));

    uint256 targetRatioDP = Math.mulDiv(targetA, precisionDenominator, targetB);

    assume(addValid(targetRatioDP, precisionNumerator));
}

function assume_getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut,
    uint256 feeNumerator,
    uint256 feeDenominator,
    function(bool) external assume
) {
    assume(amountIn > 0);

    assume(reserveIn > 0 && reserveOut > 0);

    assume(mulValid(amountIn, feeNumerator));

    assume(mulValid(amountIn * feeNumerator, reserveOut));

    assume(mulValid(reserveIn, feeDenominator));

    assume(addValid(reserveIn * feeDenominator, amountIn * feeNumerator));

    assume(feeDenominator > 0);
}

function assume_removeLiquidityDryrun(
    Estimator.Estimation memory estimation,
    Estimator.EstimationContext memory context,
    uint256 minimumBase,
    function(bool) external assume
) {
    assume(
        mulDivValid(context.totalSupply, minimumBase, estimation.reserveBase)
    );

    uint256 minimumLiquidityExpected = Math.mulDiv(
        context.totalSupply,
        minimumBase,
        estimation.reserveBase
    );

    // no "removeLiquidity: INSUFFICIENT_LIQUIDITY"
    assume(context.vaultLiquidity >= minimumLiquidityExpected);

    uint256 removeLiquidityExpected = context.vaultLiquidity -
        minimumLiquidityExpected;

    assume(mulValid(removeLiquidityExpected, estimation.reserveBase));

    assume(mulValid(removeLiquidityExpected, estimation.reserveQuote));

    assume(context.totalSupply > 0);

    assume(context.totalSupply > removeLiquidityExpected);
}

function assume_swapToRatioDryrun(
    Estimator.Estimation memory estimation,
    Estimator.EstimationContext memory context,
    uint256 targetBase,
    uint256 targetQuote,
    uint256 feeNumerator,
    uint256 feeDenominator,
    function(bool) external assume
) {
    assume_swapToRatio(
        estimation.reserveBase,
        estimation.reserveQuote,
        targetBase,
        targetQuote,
        feeNumerator,
        feeDenominator,
        assume
    );

    (bool baseToQuote, uint256 amountIn, uint256 amountOut) = Calculate
        .swapToRatio(
            estimation.reserveBase,
            estimation.reserveQuote,
            targetBase,
            targetQuote,
            feeNumerator,
            feeDenominator
        );

    uint256 availableIn = baseToQuote
        ? context.availableBase
        : context.availableQuote;

    assume(availableIn > amountIn);

    uint256 reserveIn = baseToQuote
        ? estimation.reserveBase
        : estimation.reserveQuote;

    assume(addValid(reserveIn, amountIn));

    uint256 availableOut = baseToQuote
        ? context.availableQuote
        : context.availableBase;

    assume(addValid(availableOut, amountOut));
}

function assume_addLiquidityDryrun(
    Estimator.Estimation memory estimation,
    Estimator.EstimationContext memory context,
    uint256 reserveBaseInvariant,
    function(bool) external assume
) {
    assume_addLiquidity(
        estimation.reserveBase,
        estimation.reserveQuote,
        reserveBaseInvariant,
        assume
    );

    uint256 addedBaseExpected = reserveBaseInvariant - estimation.reserveBase;

    assume(estimation.reserveBase > 0 && estimation.reserveQuote > 0);

    assume(mulValid(context.totalSupply, addedBaseExpected));

    uint256 addedQuoteExpected = Math.mulDiv(
        addedBaseExpected,
        estimation.reserveQuote,
        estimation.reserveBase
    );

    assume(mulValid(context.totalSupply, addedQuoteExpected));

    uint256 mintedLiquidityExpected = Math.min(
        (addedBaseExpected * context.totalSupply) / estimation.reserveBase,
        (addedQuoteExpected * context.totalSupply) / estimation.reserveQuote
    );

    assume(addValid(estimation.reserveBase, addedBaseExpected));

    assume(addValid(estimation.reserveQuote, addedQuoteExpected));

    assume(addValid(context.minimumLiquidity, mintedLiquidityExpected));
}

function assume_estimate(
    uint256 reserveBaseInvariant,
    uint256 availableQuote,
    uint256 targetBase,
    uint256 targetQuote,
    function(bool) external assume
) {
    assume(targetBase > 0 && targetQuote > 0);

    // available base large enough for minimum requiredBase
    // swapToRatioDryrun: not enough base
    assume(reserveBaseInvariant >= targetBase);

    assume(mulDivValid(targetQuote, reserveBaseInvariant, targetBase));

    uint256 reserveQuoteDesired = Math.mulDiv(
        targetQuote,
        reserveBaseInvariant,
        targetBase
    );

    // available quote large enough for minimum requiredQuote
    // swapToRatioDryrun: not enough quote
    assume(availableQuote >= reserveQuoteDesired);
}
