// NOTE: This is based on V4PreDeployed.s.sol
// You can make changes to base on V4Deployer.s.sol to deploy everything fresh as well

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {TornadoHook} from "../src/TornadoHook.sol";
import {Groth16Verifier} from "../src/Verifier.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import "forge-std/console.sol";

contract HookDeployer is Script {
    HelperConfig helperConfig = new HelperConfig();

    PoolManager manager = PoolManager(helperConfig.getManager());
    PoolSwapTest swapRouter = PoolSwapTest(helperConfig.getSwapRouter());
    PoolModifyLiquidityTest modifyLiquidityRouter = PoolModifyLiquidityTest(helperConfig.getModifyLiquidityRouter());
    uint256 denomination = helperConfig.getDenomination();
    uint8 merkleTreeHeight = helperConfig.getMerkleTreeHeight();
    uint160 flags = helperConfig.getHookFlags();

    Currency token0;
    Currency token1;

    address public verifier;
    address public deployer;

    PoolKey key;

    function setUp() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "forge-ffi-scripts/deployMimcsponge.js";
        bytes memory mimcspongeBytecode = vm.ffi(inputs);

        address hasher;

        deployer = vm.rememberKey(helperConfig.getDeployerKey());
        vm.label(deployer, "Deployer");

        vm.startBroadcast(deployer);

        assembly {
            hasher := create(0, add(mimcspongeBytecode, 0x20), mload(mimcspongeBytecode))
            if iszero(hasher) { revert(0, 0) }
        }

        verifier = address(new Groth16Verifier());

        MockERC20 tokenA = new MockERC20("Token0", "TK0", 18);
        MockERC20 tokenB = new MockERC20("Token1", "TK1", 18);

        if (address(tokenA) > address(tokenB)) {
            (token0, token1) = (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));
        } else {
            (token0, token1) = (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)));
        }

        tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);

        tokenA.mint(deployer, 100 * 10 ** 18);
        tokenB.mint(deployer, 100 * 10 ** 18);

        // Mine for hook address
        vm.stopBroadcast();

        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(TornadoHook).creationCode,
            abi.encode(manager, verifier, hasher, denomination, merkleTreeHeight)
        );

        vm.startBroadcast(deployer);
        TornadoHook hook = new TornadoHook{salt: salt}(manager, verifier, hasher, denomination, merkleTreeHeight);
        require(address(hook) == hookAddress, "hook address mismatch");

        key = PoolKey({currency0: token0, currency1: token1, fee: 3000, tickSpacing: 120, hooks: hook});

        // the second argument here is SQRT_PRICE_1_1
        manager.initialize(key, 79228162514264337593543950336);
        vm.stopBroadcast();

        console.log("Hook address:", address(hook));
    }

    function run() public {
        vm.startBroadcast(deployer);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: 0}),
            new bytes(0)
        );
        vm.stopBroadcast();
    }
}
