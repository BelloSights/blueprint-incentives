// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/Treasury.sol";
import "../mock/MockERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract TreasuryTest is Test {
    Treasury public treasury;
    address public owner = address(0xABCD);
    address public recipient = address(0xBEEF);

    function setUp() public {
        vm.prank(owner);
        treasury = new Treasury();
        treasury.initialize(owner);
    }

    function testReceiveETH() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        payable(address(treasury)).transfer(amount);
        assertEq(address(treasury).balance, amount, "Treasury should hold ETH");
    }

    function testWithdrawETH() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        payable(address(treasury)).transfer(amount);
        vm.prank(owner);
        treasury.withdrawETH(payable(recipient), amount);
        assertEq(address(treasury).balance, 0, "Treasury ETH balance should be zero");
    }

    function testDonateToken() public {
        // Deploy a dummy ERC20 token (MockERC20 is assumed to have a mint function)
        MockERC20 token = new MockERC20();
        uint256 donationAmount = 100 ether;

        // Mint tokens to the treasury so that it can donate them.
        token.mint(address(treasury), donationAmount);

        vm.prank(owner);
        treasury.donate(recipient, address(token), donationAmount);
        assertEq(
            token.balanceOf(recipient),
            donationAmount,
            "Recipient should have received tokens"
        );
    }
}
