// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BondToken.sol";

contract MockUSDC is IERC20 {
    string public constant name = "Mock USDC";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }
}

contract BondTokenTest is Test {
    MockUSDC public usdc;
    BondToken public bondToken;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant FACE_VALUE = 1000 * 10 ** 6; // 1000 USDC
    uint256 public constant COUPON_RATE = 500; // 5% annual
    uint256 public maturityDate;

    function setUp() public {
        usdc = new MockUSDC();

        // Set maturity date to 1 year from now
        maturityDate = block.timestamp + 365 days;

        bondToken = new BondToken(address(usdc), FACE_VALUE, COUPON_RATE, maturityDate);

        // Fund users with USDC
        usdc.mint(alice, 100_000 * 10 ** 6);
        usdc.mint(bob, 100_000 * 10 ** 6);
    }

    function test_BuyBonds() public {
        uint256 bondAmount = 10;
        uint256 totalCost = FACE_VALUE * bondAmount;

        // Alice approves and buys bonds
        vm.startPrank(alice);
        usdc.approve(address(bondToken), totalCost);
        bondToken.buy(bondAmount);
        vm.stopPrank();

        // Check bond balance
        assertEq(bondToken.balanceOf(alice), bondAmount);

        // Check USDC was deducted
        assertEq(usdc.balanceOf(alice), 100_000 * 10 ** 6 - totalCost);
        assertEq(usdc.balanceOf(address(bondToken)), totalCost);
    }

    function test_ClaimInterestAfter30Days() public {
        uint256 bondAmount = 10;
        uint256 totalCost = FACE_VALUE * bondAmount;

        // Alice buys bonds
        vm.startPrank(alice);
        usdc.approve(address(bondToken), totalCost);
        bondToken.buy(bondAmount);
        vm.stopPrank();

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        // Calculate expected interest (accounting for integer division)
        uint256 yearlyInterest = (FACE_VALUE * bondAmount * COUPON_RATE) / 10000;
        uint256 monthlyInterest = yearlyInterest / 12;

        // Check pending interest
        uint256 pending = bondToken.pendingInterest(alice);
        assertEq(pending, monthlyInterest);

        // Check Alice's USDC balance before claiming
        uint256 aliceUSDCBefore = usdc.balanceOf(alice);
        uint256 contractUSDCBefore = usdc.balanceOf(address(bondToken));

        // Claim interest
        vm.prank(alice);
        bondToken.claimInterest();

        // Check USDC was transferred and minted
        assertEq(usdc.balanceOf(alice), aliceUSDCBefore + monthlyInterest);
        assertEq(usdc.balanceOf(address(bondToken)), contractUSDCBefore); // Principal remains
        assertEq(bondToken.claimedInterest(alice), monthlyInterest);
    }

    function test_RedeemAtMaturity() public {
        uint256 bondAmount = 10;
        uint256 totalCost = FACE_VALUE * bondAmount;

        // Alice buys bonds
        vm.startPrank(alice);
        usdc.approve(address(bondToken), totalCost);
        bondToken.buy(bondAmount);
        vm.stopPrank();

        // Fast forward to maturity
        vm.warp(maturityDate);

        // Calculate expected interest for full year
        uint256 yearlyInterest = (FACE_VALUE * bondAmount * COUPON_RATE) / 10000;

        // Check pending interest (use approximate comparison due to rounding)
        uint256 pending = bondToken.pendingInterest(alice);
        assertApproxEqAbs(pending, yearlyInterest, 10, "Interest should be approximately equal");

        // Check balances before redemption
        uint256 aliceUSDCBefore = usdc.balanceOf(alice);
        // uint256 contractUSDCBefore = usdc.balanceOf(address(bondToken));

        // Redeem
        vm.prank(alice);
        bondToken.redeem();

        // Check balances after redemption
        uint256 expectedTotal = totalCost + yearlyInterest;
        assertApproxEqAbs(
            usdc.balanceOf(alice), aliceUSDCBefore + expectedTotal, 10, "Total redemption should be approximately equal"
        );
        assertEq(usdc.balanceOf(address(bondToken)), 0); // Contract should have no USDC left
        assertEq(bondToken.balanceOf(alice), 0);
    }

    function test_CannotRedeemBeforeMaturity() public {
        uint256 bondAmount = 10;
        uint256 totalCost = FACE_VALUE * bondAmount;

        // Alice buys bonds
        vm.startPrank(alice);
        usdc.approve(address(bondToken), totalCost);
        bondToken.buy(bondAmount);
        vm.stopPrank();

        // Try to redeem before maturity - should fail
        vm.prank(alice);
        vm.expectRevert("Not matured yet");
        bondToken.redeem();
    }

    function test_NoInterestForZeroBalance() public {
        // Check that address with no bonds has no pending interest
        uint256 pending = bondToken.pendingInterest(alice);
        assertEq(pending, 0);

        // Try to claim interest with no bonds - should fail
        vm.prank(alice);
        vm.expectRevert("No interest");
        bondToken.claimInterest();
    }

    function test_MultipleInterestClaims() public {
        uint256 bondAmount = 10;
        uint256 totalCost = FACE_VALUE * bondAmount;

        // Alice buys bonds
        vm.startPrank(alice);
        usdc.approve(address(bondToken), totalCost);
        bondToken.buy(bondAmount);
        vm.stopPrank();

        // Fast forward 30 days and claim
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        bondToken.claimInterest();

        // Fast forward another 30 days and claim again
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        bondToken.claimInterest();

        // Should have claimed 2 months of interest (use approximate comparison)
        uint256 yearlyInterest = (FACE_VALUE * bondAmount * COUPON_RATE) / 10000;
        uint256 twoMonthsInterest = (yearlyInterest * 2) / 12;
        assertApproxEqAbs(
            bondToken.claimedInterest(alice), twoMonthsInterest, 1, "Two months interest should be approximately equal"
        );
    }
}
