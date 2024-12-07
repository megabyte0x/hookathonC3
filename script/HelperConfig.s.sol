// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract HelperConfig is Script {
    function getManager() public view returns (address) {
        address manager = DevOpsTools.get_most_recent_deployment("PoolManager", 31337);
        return manager;
    }

    function getSwapRouter() public view returns (address) {
        address swapRouter = DevOpsTools.get_most_recent_deployment("PoolSwapTest", 31337);
        return swapRouter;
    }

    function getModifyLiquidityRouter() public view returns (address) {
        address modifyLiquidityRouter = DevOpsTools.get_most_recent_deployment("PoolModifyLiquidityTest", 31337);
        return modifyLiquidityRouter;
    }

    function getVerifier() public view returns (address) {
        address verifier = DevOpsTools.get_most_recent_deployment("Groth16Verifier", 31337);
        return verifier;
    }

    function getHasher() public view returns (address) {
        address hasher = DevOpsTools.get_most_recent_deployment("Mimcsponge", 31337);
        return hasher;
    }

    function getDenomination() public view returns (uint256) {
        return 1 ether;
    }

    function getMerkleTreeHeight() public view returns (uint8) {
        return 31;
    }

    function getHookFlags() public view returns (uint160) {
        return uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG);
    }

    function getDeployerKey() public view returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }

    function getHookAddress() public view returns (address) {
        address hookAddress = DevOpsTools.get_most_recent_deployment("TornadoHook", 31337);
        return hookAddress;
    }
}
