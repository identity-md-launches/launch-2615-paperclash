// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {PaperclashToken} from "../src/PaperclashToken.sol";

/// @title Deploy script for Paperclash (PAPER)
/// @notice Reviewable reference deployment. The production launch is performed by the IMD
/// ProjectFactory from the attested bytecode, not by this script; it exists so the deployment can be
/// read, and rehearsed on a local chain, as plain code.
/// @dev The token has no constructor arguments and no post-deploy configuration, so `deploy()` takes
/// none. Tests call `deploy()` directly; `run()` only wraps it in a broadcast and reads nothing from
/// the environment.
contract DeployPaperclash is Script {
    /// @notice Deploys the token. The caller of this function's `new` becomes the holder of the supply.
    function deploy() public returns (PaperclashToken token) {
        token = new PaperclashToken();
    }

    /// @notice Broadcast entry point for `forge script`. The broadcasting signer receives the supply.
    function run() external returns (PaperclashToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
