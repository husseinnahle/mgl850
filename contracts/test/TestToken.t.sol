// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Fixture} from "./utils/Fixture.sol";

/// @notice EF-10 : deux jetons ERC-20 de test, une garantie et un actif empruntable.
contract TestTokenTest is Fixture {
    function test_Metadata() public view {
        assertEq(usdc.name(), "Test USD Coin");
        assertEq(usdc.symbol(), "tUSDC");
        assertEq(usdc.decimals(), 6);

        assertEq(eth.name(), "Test Ether");
        assertEq(eth.symbol(), "tETH");
        assertEq(eth.decimals(), 18);
    }

    function test_Faucet_GivesFixedAmountToCaller() public {
        vm.startPrank(stranger);
        usdc.faucet();
        eth.faucet();
        vm.stopPrank();

        assertEq(usdc.balanceOf(stranger), 10_000 * USDC);
        assertEq(eth.balanceOf(stranger), 10 * ETH);
    }

    function test_Mint_ByOwner() public {
        vm.prank(admin);
        usdc.mint(stranger, 5 * USDC);

        assertEq(usdc.balanceOf(stranger), 5 * USDC);
    }

    function test_Mint_RevertWhen_CallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        usdc.mint(stranger, 1);
    }
}
