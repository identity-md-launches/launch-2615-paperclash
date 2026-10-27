// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PaperclashToken} from "../src/PaperclashToken.sol";

/// @notice Edge inputs the main suite does not pin: the whole supply, allowance overwrites, a holder
/// pulling from itself, zero-amount pulls and the zero address on every side of a call.
contract PaperclashTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal constant DEPLOYER = address(0xDE91);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    PaperclashToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new PaperclashToken();
    }

    function test_transferWholeSupplyThenNothingLeft() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);

        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, 0, 1));
        token.transfer(ALICE, 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(DEPLOYER);
        token.approve(ALICE, 10 ether);
        token.approve(ALICE, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, ALICE), 3 ether);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 3 ether, 4 ether)
        );
        token.transferFrom(DEPLOYER, ALICE, 4 ether);
    }

    function test_revokedAllowanceBlocksPull() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10 ether);
        vm.prank(DEPLOYER);
        token.approve(ALICE, 0);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        token.transferFrom(DEPLOYER, ALICE, 1);
    }

    function test_allowanceIsSpentExactlyThenExhausted() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 5 ether);

        vm.startPrank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 2 ether);
        token.transferFrom(DEPLOYER, BOB, 3 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        token.transferFrom(DEPLOYER, BOB, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(BOB), 5 ether);
    }

    /// @dev Holding tokens is not an allowance over them: pulling from yourself needs an approval too.
    function test_selfTransferFromNeedsAllowance() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        token.transferFrom(DEPLOYER, ALICE, 1);

        vm.startPrank(DEPLOYER);
        token.approve(DEPLOYER, 1);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(DEPLOYER, DEPLOYER), 0);
    }

    function test_zeroAmountTransferFromWithoutAllowanceSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 0));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10 ether);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(DEPLOYER, address(0), 1 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), 10 ether, "a reverted pull must not spend the allowance");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    /// @dev The zero address holds nothing and has approved nobody, so nothing can be pulled from it.
    function test_transferFromZeroAddressReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        token.transferFrom(address(0), BOB, 1);
    }

    function test_infiniteAllowanceSpendEmitsNoApproval() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);

        vm.recordLogs();
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1 ether);
        assertEq(vm.getRecordedLogs().length, 1, "only the Transfer event");
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max);
    }

    function test_zeroAmountApproveEmits() public {
        vm.prank(ALICE);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(ALICE, BOB, 0);
        assertTrue(token.approve(BOB, 0));
        assertEq(token.allowance(ALICE, BOB), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactly(address owner, address spender, uint256 amount) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotPull(address stranger, uint256 amount) public {
        stranger = address(uint160(bound(uint160(stranger), 1, type(uint160).max)));
        if (stranger == DEPLOYER) stranger = ALICE;
        amount = bound(amount, 1, SUPPLY);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(DEPLOYER, stranger, amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }
}
