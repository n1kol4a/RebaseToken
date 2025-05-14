//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private token;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public SEND_VALUE = 1e5;

    function setUp() public {
        vm.deal(owner, 1 ether);
        vm.startPrank(owner);
        token = new RebaseToken();
        vault = new Vault(IRebaseToken(address(token)));
        token.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1 * 10 ** 18}("");
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardsAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardsAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1 * 10 ** 4, type(uint96).max);
        //deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        //check rebase token balance
        uint256 startBalance = token.balanceOf(user);
        console.log("Balance: ", startBalance);
        assertEq(startBalance, amount);
        //warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = token.balanceOf(user);
        assertGt(middleBalance, startBalance);
        //warp the time agiant by the same amount to check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = token.balanceOf(user);
        assertGt(endBalance, middleBalance);
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        //deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        //redeem
        vault.redeem(type(uint256).max);
        assertEq(token.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 amount, uint256 time) public {
        time = bound(time, 1000, 365 days * 10);
        amount = bound(amount, 1e5, type(uint96).max);
        //1.deposit

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        //2.warp the time
        vm.warp(block.timestamp + time);
        uint256 balance = token.balanceOf(user);
        //2(b) add rewards to the vault
        vm.deal(owner, balance - amount);
        vm.prank(owner);
        addRewardsToVault(balance - amount);
        //3.redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethbalance = address(user).balance;
        assertEq(ethbalance, balance);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e3, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address userTwo = makeAddr("userTwo");
        uint256 userBalance = token.balanceOf(user);
        uint256 userTwoBalance = token.balanceOf(userTwo);
        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        // Update the interest rate so we can check the user interest rates are different after transferring
        vm.prank(owner);
        token.setInterestRate(4e10);

        // Send half the balance to another user
        vm.prank(user);
        token.transfer(userTwo, amountToSend);
        uint256 userBalanceAfterTransfer = token.balanceOf(user);
        uint256 userTwoBalancAfterTransfer = token.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalancAfterTransfer, userTwoBalance + amountToSend);
        // After some time has passed, check the balance of the two users has increased
        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = token.balanceOf(user);
        uint256 userTwoBalanceAfterWarp = token.balanceOf(userTwo);
        // check their interest rates are as expected
        // since user two hadnt minted before, their interest rate should be the same as in the contract
        uint256 userTwoInterestRate = token.getUserInterestRate(userTwo);
        assertEq(userTwoInterestRate, 5e10);
        // since user had minted before, their interest rate should be the previous interest rate
        uint256 userInterestRate = token.getUserInterestRate(user);
        assertEq(userInterestRate, 5e10);

        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(userTwoBalanceAfterWarp, userTwoBalancAfterTransfer);
    }
       function testSetInterestRate(uint256 newInterestRate) public {
        // bound the interest rate to be less than the current interest rate
        newInterestRate = bound(newInterestRate, 0, token.getInterestRate() - 1);
        // Update the interest rate
        vm.startPrank(owner);
        token.setInterestRate(newInterestRate);
        uint256 interestRate = token.getInterestRate();
        assertEq(interestRate, newInterestRate);
        vm.stopPrank();

        // check that if someone deposits, this is their new interest rate
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        uint256 userInterestRate = token.getUserInterestRate(user);
        vm.stopPrank();
        assertEq(userInterestRate, newInterestRate);
    }
    function testCannotSetInterestRate(uint256 newInterestRate) public {
        // Update the interest rate
        vm.startPrank(user);
        vm.expectRevert();
        token.setInterestRate(newInterestRate);
        vm.stopPrank();
    }
    
    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = token.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate+1, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        token.setInterestRate(newInterestRate);
        assertEq(token.getInterestRate(), initialInterestRate);
    }
     function testGetPrincipleAmount() public {
        uint256 amount = 1e5;
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleAmount = token.principalBalanceOf(user);
        assertEq(principleAmount, amount);

        // check that the principle amount is the same after some time has passed
        vm.warp(block.timestamp + 1 days);
        uint256 principleAmountAfterWarp = token.principalBalanceOf(user);
        assertEq(principleAmountAfterWarp, amount);
    }
}
