// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import {Tornado} from "./Tornado.sol";

contract TornadoHook is BaseHook, Tornado {
    // Use CurrencyLibrary and BalanceDeltaLibrary
    // to add some helper functions over the Currency and BalanceDelta
    // data types
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    address public eigenLayerAVS;

    constructor(
        IPoolManager _manager,
        address _verifier,
        address _hasher,
        uint256 _denomination,
        uint8 _merkleTreeHeight
    ) BaseHook(_manager) Tornado(_verifier, _hasher, _denomination, _merkleTreeHeight) {}

    // Set up hook permissions to return `true`
    // for the two hook functions we are using
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterAddLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Stub implementation for `afterAddLiquidity`
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (!key.currency0.isAddressZero()) return (this.afterAddLiquidity.selector, delta);

        uint256 ethSpend = uint256(int256(-delta.amount0()));

        // call create new task on Eigen Layer AVS contract using only the contract address and function signature 0x194b7b18
        (bool success,) = eigenLayerAVS.call(abi.encodeWithSelector(0x194b7b18));
        require(success, "create new task call failed");

        return (this.afterAddLiquidity.selector, delta);
    }

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4) {
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, bytes32 root, bytes32 nullifierHash) =
            abi.decode(hookData, (uint256[2], uint256[2][2], uint256[2], bytes32, bytes32));

        bool isCorrect = withdraw(pA, pB, pC, root, nullifierHash, address(0), 0, 0);

        require(isCorrect, "Invalid withdraw proof");

        return this.beforeRemoveLiquidity.selector;
    }

    function setEigenLayerAVS(address _eigenLayerAVS) public {
        eigenLayerAVS = _eigenLayerAVS;
    }
}
