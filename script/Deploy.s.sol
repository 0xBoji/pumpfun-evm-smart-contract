// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/PumpFun.sol";
import "../contracts/TokenFactory.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        
        uint256 createFee = 0.1 ether;
        uint256 basisFee = 100; // 1%

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PumpFun
        PumpFun pumpFun = new PumpFun(
            feeRecipient,
            createFee,
            basisFee
        );

        // Deploy TokenFactory
        TokenFactory tokenFactory = new TokenFactory();
        tokenFactory.setPoolAddress(address(pumpFun));

        vm.stopBroadcast();

        console.log("PumpFun deployed to:", address(pumpFun));
        console.log("TokenFactory deployed to:", address(tokenFactory));
    }
} 