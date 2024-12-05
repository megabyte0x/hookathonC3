// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import "forge-std/console.sol";

import {PointsHook} from "../src/PointsHook.sol";

contract TestPointsHook is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC20 public token;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    PointsHook public hook;

    function setUp() public {
        // deploy pool manager and router contracts

        deployFreshManagerAndRouters();

        // deploy token
        token = new MockERC20("Points", "PTS", 18);
        tokenCurrency = Currency.wrap(address(token));

        // mint tokens to ourself
        token.mint(address(this), 1000e18);

        //deploy hook to an address that has flags set
        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG);

        deployCodeTo("PointsHook.sol", abi.encode(manager, "Points Token", "TEST_POINTS"), address(flags));

        // deploy hook
        hook = PointsHook(address(flags));

        // approve token for swap router and modify liquidity router
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // initialize pool
        (key,) = initPool(ethCurrency, tokenCurrency, hook, 3000, SQRT_PRICE_1_1);
    }

    function test_addLiquidityAndSwap() public {
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this));

        // set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.1 ether;

        // Calculating Liquidity delta for adding 0.1 eth of token0
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceAtTickLower, SQRT_PRICE_1_1, ethToAdd);

        // Caculating the amount of token1 to add for the given liquidity delta
        uint256 tokenToAdd =
            LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

        // Adding liquidity to the pool
        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            hookData
        );

        uint256 pointsBalanceAfterAddLiquidity = hook.balanceOf(address(this));

        assertApproxEqAbs(pointsBalanceAfterAddLiquidity - pointsBalanceOriginal, 0.1 ether, 0.001 ether);

        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));

        assertEq(pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity, 2 * 10 ** 14);
    }
}
