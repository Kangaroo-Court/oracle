// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import "../src/00_GettingStarted.sol";


//forge script OO_GettingStartedScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

contract OO_GettingStartedScript is Script {

    function run() public {
        console.log("Running script");
        vm.broadcast();
        OO_GettingStarted gs = new OO_GettingStarted();
    }
}