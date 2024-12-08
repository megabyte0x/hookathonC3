// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {TornadoHook} from "../src/TornadoHook.sol";
import "forge-std/console.sol";

contract SetAVSAddress is Script {
    HelperConfig helperConfig = new HelperConfig();
    address eigenLayerAVS = 0x4bf010f1b9beDA5450a8dD702ED602A104ff65EE;
    address deployer = vm.rememberKey(helperConfig.getDeployerKey());

    function run() public {
        vm.label(deployer, "Deployer");
        address hookAddress = helperConfig.getHookAddress();
        console.log("Hook address:", hookAddress);

        vm.startBroadcast(deployer);
        TornadoHook(hookAddress).setEigenLayerAVS(eigenLayerAVS);
        vm.stopBroadcast();
    }
}
