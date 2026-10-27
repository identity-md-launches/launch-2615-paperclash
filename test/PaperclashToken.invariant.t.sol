// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PaperclashToken} from "../src/PaperclashToken.sol";

/// @notice Drives the token with random transfers, approvals and pulls among a fixed set of actors,
/// including the calls that must fail, and keeps an independent model of every balance and allowance.
/// @dev Each failure path is driven with `expectRevert`, and the suite runs with fail-on-revert, so a
/// call that succeeds where it must fail, or fails where it must succeed, breaks the run.
contract PaperclashHandler is Test {
    PaperclashToken public immutable token;
    address[] internal actors;

    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;

    uint256 public transfersOk;
    uint256 public pullsOk;
    uint256 public rejected;
    /// @dev Total value moved by successful calls; the supply must not care.
    uint256 public volume;

    constructor(PaperclashToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            modelBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, modelBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
        transfersOk++;
        volume += amount;
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = modelBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transfer(to, amount);
        rejected++;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, modelBalance[from]);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        rejected++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Mostly realistic amounts, sometimes the infinite allowance.
        if (amount % 5 == 0) amount = type(uint256).max;
        else amount = bound(amount, 0, 2 * token.TOTAL_SUPPLY());

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = modelAllowance[owner][spender];
        uint256 held = modelBalance[owner];
        amount = bound(amount, 0, allowed < held ? allowed : held);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) modelAllowance[owner][spender] = allowed - amount;
        modelBalance[owner] -= amount;
        modelBalance[to] += amount;
        pullsOk++;
        volume += amount;
    }

    function transferFromAboveAllowance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = modelAllowance[owner][spender];
        if (allowed == type(uint256).max) return; // nothing exceeds an infinite allowance
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        token.transferFrom(owner, to, amount);
        rejected++;
    }

    function transferFromAboveBalance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = modelAllowance[owner][spender];
        uint256 held = modelBalance[owner];
        if (allowed <= held) return; // the allowance check would fire first
        uint256 amount = held + bound(excess, 1, allowed - held);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        token.transferFrom(owner, to, amount);
        rejected++;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        rejected++;
    }

    /// @dev A stranger with no balance and no allowance tries every way of taking an actor's tokens.
    function strangerPull(address stranger, uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        for (uint256 i; i < actors.length; ++i) {
            if (stranger == actors[i]) return;
        }
        if (stranger == address(0) || stranger == address(this)) return;
        amount = bound(amount, 1, token.TOTAL_SUPPLY());

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(owner, stranger, amount);
        rejected++;
    }
}

contract PaperclashTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    PaperclashToken internal token;
    PaperclashHandler internal handler;

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new PaperclashToken();

        address[] memory actors = new address[](5);
        actors[0] = deployer;
        actors[1] = makeAddr("alice");
        actors[2] = makeAddr("bob");
        actors[3] = makeAddr("pool");
        actors[4] = makeAddr("distributor");

        handler = new PaperclashHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actorAt(i);
            assertEq(token.balanceOf(a), handler.modelBalance(a));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address owner = handler.actorAt(i);
                address spender = handler.actorAt(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowance(owner, spender));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "Paperclash");
        assertEq(token.symbol(), "PAPER");
        assertEq(token.decimals(), 18);
    }
}
