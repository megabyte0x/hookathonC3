// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Foundry libraries
import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {console} from "forge-std/console.sol";

// Our contracts
import {TakeProfitsHook} from "../src/TakeProfitsHook.sol";

contract TakeProfitsHookTest is Test, Deployers {
    // Use the libraries
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // The two currencies (tokens) from the pool
    Currency token0;
    Currency token1;

    TakeProfitsHook hook;

    function setUp() public {
        deployFreshManagerAndRouters();

        (token0, token1) = deployMintAndApprove2Currencies();

        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);
        address hookAddress = address(flags);
        deployCodeTo("TakeProfitsHook.sol", abi.encode(manager, ""), hookAddress);
        hook = TakeProfitsHook(hookAddress);

        MockERC20(Currency.unwrap(token0)).approve(address(hook), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), type(uint256).max);

        (key,) = initPool(token0, token1, hook, 3000, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_placeOrder() public {
        int24 tick = 100;
        uint256 amount = 10e18;
        bool zeroForOne = true;

        uint256 originalBalance = token0.balanceOfSelf();
        int24 tickLower = hook.placeOrder(key, tick, zeroForOne, amount);
        uint256 newBalance = token0.balanceOfSelf();

        assertEq(tickLower, 60);
        assertEq(newBalance, originalBalance - amount);

        uint256 positionId = hook.getPositionId(key, tickLower, zeroForOne);
        uint256 tokenBalance = hook.balanceOf(address(this), positionId);

        assertTrue(positionId != 0);
        assertEq(tokenBalance, amount);
    }

    function test_cancelOrder() public {
        int24 tick = 100;
        uint256 amount = 10e18;
        bool zeroForOne = true;

        uint256 originalBalance = token0.balanceOfSelf();
        int24 tickLower = hook.placeOrder(key, tick, zeroForOne, amount);
        uint256 newBalance = token0.balanceOfSelf();

        assertEq(tickLower, 60);
        assertEq(newBalance, originalBalance - amount);

        uint256 positionId = hook.getPositionId(key, tickLower, zeroForOne);
        uint256 tokenBalanceBefore = hook.balanceOf(address(this), positionId);

        assertEq(tokenBalanceBefore, amount);

        hook.cancelOrder(key, tickLower, zeroForOne, amount / 2);
        uint256 finalBalance = token0.balanceOfSelf();
        console.log("originalBalance", originalBalance);
        console.log("newBalance", newBalance);
        console.log("finalBalance", finalBalance);

        assertEq(finalBalance + amount / 2, originalBalance);

        uint256 tokenBalanceAfter = hook.balanceOf(address(this), positionId);
        assertEq(tokenBalanceAfter, amount / 2);
    }

    function test_orderExecute_zeroForOne() public {
        int24 tick = 100;
        uint256 amount = 1 ether;
        bool zeroForOne = true;

        int24 tickLower = hook.placeOrder(key, tick, zeroForOne, amount);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: !zeroForOne,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, params, settings, ZERO_BYTES);

        uint256 pendingTokensForPosition = hook.pendingOrders(key.toId(), tickLower, zeroForOne);
        assertEq(pendingTokensForPosition, 0);

        uint256 positionId = hook.getPositionId(key, tickLower, zeroForOne);
        uint256 claimableOutputTokens = hook.claimableOutputTokens(positionId);
        uint256 hookContractToken1Balance = token1.balanceOf(address(hook));
        assertEq(claimableOutputTokens, hookContractToken1Balance);

        uint256 originalToken1Balance = token1.balanceOfSelf();
        hook.redeem(key, tick, zeroForOne, amount);
        uint256 newToken1Balance = token1.balanceOfSelf();

        assertEq(newToken1Balance - originalToken1Balance, claimableOutputTokens);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
