// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PaperclashToken} from "../src/PaperclashToken.sol";
import {DeployPaperclash} from "../script/DeployPaperclash.s.sol";

/// @notice Stands in for the launch factory: deploys the token so that `msg.sender` in the token's
/// constructor is this contract, exactly as ProjectFactory.launchCustom does, then pays the supply out.
contract FactoryStub {
    function deploy(bytes32 salt) external returns (PaperclashToken token) {
        token = new PaperclashToken{salt: salt}();
    }

    function move(PaperclashToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract PaperclashTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant SWARM_BPS = 1_000;
    uint256 internal constant POOL_BPS = 8_000;

    address internal constant DEPLOYER = address(0xDE91);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL = address(0x9001);
    address internal constant REQUESTER = address(0x5EC0);

    PaperclashToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new PaperclashToken();
    }

    // ----------------------------------------------------------------------------------------------
    // Metadata and supply
    // ----------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Paperclash");
        assertEq(token.symbol(), "PAPER");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "Paperclash");
        assertEq(token.TOKEN_SYMBOL(), "PAPER");
        assertEq(token.DECIMALS(), 18);
        assertEq(token.DESCRIPTION(), "Powered by imd");
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_wholeSupplyMintedToDeployerOnce() public view {
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        PaperclashToken fresh = new PaperclashToken();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(ALICE), SUPPLY);
    }

    /// @dev Whatever deploys the token holds the supply: a contract through CREATE2, as the factory does.
    function test_contractDeployerThroughCreate2HoldsSupply() public {
        FactoryStub factory = new FactoryStub();
        PaperclashToken deployed = factory.deploy(bytes32(uint256(42)));
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_deployScriptFunctionMintsToCaller() public {
        DeployPaperclash script = new DeployPaperclash();
        PaperclashToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY);
        assertEq(deployed.name(), "Paperclash");
        assertEq(deployed.symbol(), "PAPER");
    }

    // ----------------------------------------------------------------------------------------------
    // transfer
    // ----------------------------------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        vm.prank(DEPLOYER);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(DEPLOYER, ALICE, 1_000 ether);
        assertTrue(token.transfer(ALICE, 1_000 ether));
        assertEq(token.balanceOf(ALICE), 1_000 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(DEPLOYER, 5 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(BOB, 1);
    }

    function test_transferRevertsWhenExceedingBalanceByOne() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ----------------------------------------------------------------------------------------------
    // approve / transferFrom
    // ----------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(ALICE);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(ALICE, BOB, 7 ether);
        assertTrue(token.approve(BOB, 7 ether));
        assertEq(token.allowance(ALICE, BOB), 7 ether);
    }

    function test_approveToZeroAddressReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromWithinAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, 60 ether);

        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 40 ether));
        assertEq(token.balanceOf(ALICE), 60 ether);
        assertEq(token.balanceOf(CAROL), 40 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, BOB), 20 ether);
    }

    function test_transferFromInfiniteAllowanceIsNotDecremented() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);

        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 100 ether);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max);
        assertEq(token.balanceOf(CAROL), 100 ether);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(ALICE, CAROL, 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    function test_transferFromAboveAllowanceReverts() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 10 ether, 11 ether)
        );
        token.transferFrom(ALICE, CAROL, 11 ether);
    }

    function test_transferFromAboveBalanceRevertsEvenWithAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 5 ether);
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 5 ether, 6 ether));
        token.transferFrom(ALICE, CAROL, 6 ether);
    }

    /// @dev The deployer, the most plausibly trusted address, cannot pull a holder's tokens without approval.
    function test_deployerCannotTransferFromHolderWithoutApproval() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);

        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    // ----------------------------------------------------------------------------------------------
    // Launch flows: every transfer arrives whole, so the factory's distribution is exact
    // ----------------------------------------------------------------------------------------------

    function test_launchDistributionArrivesWhole() public {
        FactoryStub factory = new FactoryStub();
        PaperclashToken launched = factory.deploy(bytes32(uint256(1)));

        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(factory.move(launched, DISTRIBUTOR, swarm));
        assertTrue(factory.move(launched, POOL, pool));
        assertTrue(factory.move(launched, REQUESTER, remainder));

        assertEq(launched.balanceOf(DISTRIBUTOR), swarm);
        assertEq(launched.balanceOf(POOL), pool);
        assertEq(launched.balanceOf(REQUESTER), remainder);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);

        // A claim from the distributor arrives whole as well.
        vm.prank(DISTRIBUTOR);
        assertTrue(launched.transfer(ALICE, swarm));
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.balanceOf(DISTRIBUTOR), 0);
    }

    function test_roundTripThroughPoolPreservesBalances() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000 ether);

        vm.prank(ALICE);
        token.transfer(POOL, 1_000 ether);
        vm.prank(POOL);
        token.transfer(ALICE, 1_000 ether);

        assertEq(token.balanceOf(ALICE), 1_000 ether);
        assertEq(token.balanceOf(POOL), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ----------------------------------------------------------------------------------------------
    // No admin surface: nothing mints, pauses, freezes, seizes or upgrades
    // ----------------------------------------------------------------------------------------------

    function test_noMintOrAdminSelectorIncreasesSupply() public {
        address attacker = address(0xBEEF);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool okAttacker,) = address(token).call(data);
            assertFalse(okAttacker, signatures[i]);
            vm.prank(DEPLOYER);
            (bool okDeployer,) = address(token).call(data);
            assertFalse(okDeployer, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    function test_noPrivilegedSelectorMovesOrFreezesHolder() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);

        string[13] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "burn(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.balanceOf(ALICE), held);

        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2));
        assertEq(token.balanceOf(BOB), held / 2);
        assertEq(token.balanceOf(ALICE), held - held / 2);
    }

    function test_noOwnerAccessor() public {
        (bool ok, bytes memory ret) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
        assertEq(ret.length, 0);
    }

    function test_rejectsEtherAndUnknownCalls() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token accepted ether");
        (ok,) = address(token).call(abi.encodeWithSignature("nonexistent()"));
        assertFalse(ok, "token answered an unknown selector");
    }

    /// @dev The same reachable-opcode scan the launch floor runs: no DELEGATECALL, CALLCODE or SELFDESTRUCT.
    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ----------------------------------------------------------------------------------------------
    // Fuzz: conservation and exactness
    // ----------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupplyAndIsExact(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        amount = bound(amount, 0, SUPPLY);

        vm.prank(DEPLOYER);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), held);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 held, uint256 allowed, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(BOB, allowed);

        vm.prank(BOB);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, allowed, amount)
            );
            token.transferFrom(ALICE, CAROL, amount);
            assertEq(token.balanceOf(ALICE), held);
            assertEq(token.allowance(ALICE, BOB), allowed);
        } else if (amount > held) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
            token.transferFrom(ALICE, CAROL, amount);
            assertEq(token.balanceOf(ALICE), held);
            assertEq(token.allowance(ALICE, BOB), allowed);
        } else {
            assertTrue(token.transferFrom(ALICE, CAROL, amount));
            assertEq(token.balanceOf(ALICE), held - amount);
            assertEq(token.balanceOf(CAROL), amount);
            assertEq(token.allowance(ALICE, BOB), allowed - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_multiHopTransfersConserveSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);

        vm.prank(DEPLOYER);
        token.transfer(ALICE, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        vm.prank(BOB);
        token.transfer(CAROL, c);

        assertEq(token.balanceOf(DEPLOYER), SUPPLY - a);
        assertEq(token.balanceOf(ALICE), a - b);
        assertEq(token.balanceOf(BOB), b - c);
        assertEq(token.balanceOf(CAROL), c);
        assertEq(
            token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(CAROL), SUPPLY
        );
        assertEq(token.totalSupply(), SUPPLY);
    }
}
