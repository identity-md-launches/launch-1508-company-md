// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "../src/CompanyToken.sol";

/// @dev Complements the deployment and basic ERC-20 tests with arithmetic boundaries,
/// approval lifecycle checks and algebraic properties. Balances come only from real transfers.
/// forge-config: default.fuzz.runs = 1000
contract CompanyTokenBoundaryTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CompanyToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        alice = makeAddr("boundary alice");
        bob = makeAddr("boundary bob");
        spender = makeAddr("boundary spender");
        token = new CompanyToken();
    }

    function test_OneWeiTransferRoundTripIsExact() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumAmountCannotOverflowDirectOrDelegatedTransfer() public {
        uint256 maximum = type(uint256).max;
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(error);
        token.transfer(alice, maximum);

        token.approve(spender, maximum);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);

        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferAboveBalanceStillReverts() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DelegatedSelfTransferAboveBalanceRollsBackAllowance() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsConsumed() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_InfiniteApprovalCanBeReplacedAndRevoked() public {
        token.approve(spender, type(uint256).max);
        token.approve(spender, 1);
        assertEq(token.allowance(address(this), spender), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);

        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_InfiniteApprovalSurvivesEmptyBalanceAndRefill() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        vm.prank(alice);
        token.transfer(address(this), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerUsingTransferFromStillNeedsSelfApproval() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.startPrank(alice);
        token.approve(alice, 1);
        assertTrue(token.transferFrom(alice, bob, 1));
        vm.stopPrank();
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_ApprovalsDoNotGrantTransitiveAuthority() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, 10);
        vm.prank(bob);
        token.approve(spender, 10);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, spender, 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, bob), 10);
        assertEq(token.allowance(bob, spender), 10);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_ApprovalBeforeFundingCanOnlyBeSpentAfterFunding() public {
        vm.prank(alice);
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(bob), 0);

        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_ZeroSpenderRejectsZeroAndMaximumApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroOwnerCannotMintEvenZeroAmount() public {
        // No dependency on error ordering between allowance validation and sender validation.
        vm.prank(spender);
        (bool zeroAccepted,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), alice, 0)));
        assertFalse(zeroAccepted);
        vm.prank(spender);
        (bool oneAccepted,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), alice, 1)));
        assertFalse(oneAccepted);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesFiniteApproval() public {
        token.approve(spender, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_TransfersRoundTripWithExistingRecipientBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - held);
        token.transfer(alice, held);
        token.transfer(alice, amount);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersEqualSingleTransfer(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        CompanyToken single = new CompanyToken();
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, second));
        assertTrue(single.transfer(alice, first + second));
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalsAndSpendsAreIsolatedByOwnerAndSpender(uint256 first, uint256 second) public {
        first = bound(first, 1, SUPPLY / 2);
        second = bound(second, 1, SUPPLY / 2);
        token.transfer(alice, first);
        token.transfer(bob, second);
        vm.prank(alice);
        token.approve(spender, first);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.approve(spender, second);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, first));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.allowance(bob, spender), second);
        assertEq(token.balanceOf(bob), second);

        vm.prank(spender);
        assertTrue(token.transferFrom(bob, spender, second));
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), first + second);
        assertEq(token.balanceOf(address(this)), SUPPLY - first - second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);

        token.transfer(alice, amount - held);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
