// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";

import {GasPriceFeesHook} from "../src/GasPriceFeesHook.sol";

contract TestGasPriceFeesHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolId;

    GasPriceFeesHook hook;

    function setUp() public {
        deployFreshManagerAndRouters();

        deployMintAndApprove2Currencies();

        address hookAddress =
            address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));

        vm.txGasPrice(10 gwei);
        deployCodeTo("GasPriceFeesHook.sol", abi.encode(manager), hookAddress);

        hook = GasPriceFeesHook(hookAddress);

        (key,) = initPool(currency0, currency1, hook, LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_feeUpdatesWithGasPrice() public {
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.00001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        uint128 gasPrice = uint128(tx.gasprice);
        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint104 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(gasPrice, 10 gwei);
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 1);

        // AT 10 gwei

        uint256 balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfToken1After = currency1.balanceOfSelf();
        uint256 outputFromBaseFeeSwap = balanceOfToken1After - balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 2);

        // AT 4 gwei

        vm.txGasPrice(4 gwei);
        balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balanceOfToken1After = currency1.balanceOfSelf();
        uint256 outputFromIncreasedFeeSwap = balanceOfToken1After - balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 8 gwei);
        assertEq(movingAverageGasPriceCount, 3);

        // AT 12 gwei

        vm.txGasPrice(12 gwei);
        balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balanceOfToken1After = currency1.balanceOfSelf();
        uint256 outputFromDecreasedFeeSwap = balanceOfToken1After - balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 9 gwei);
        assertEq(movingAverageGasPriceCount, 4);

        console.log("BaseFee Output", outputFromBaseFeeSwap);
        console.log("IncreasedFee Output", outputFromIncreasedFeeSwap);
        console.log("DecreasedFee Output", outputFromDecreasedFeeSwap);

        assertGt(outputFromDecreasedFeeSwap, outputFromIncreasedFeeSwap);
        assertGt(outputFromBaseFeeSwap, outputFromIncreasedFeeSwap);
    }
}
