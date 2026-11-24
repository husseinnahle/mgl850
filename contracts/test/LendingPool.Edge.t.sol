// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingPool} from "../src/LendingPool.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice Cas limites du pool : montants infimes, oracle sans prix, mauvaise configuration.
contract LendingPoolEdgeTest is Fixture {
    function test_Constructor_RevertWhen_AnAddressIsZero() public {
        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new LendingPool(address(0), address(eth), address(rwa), address(oracle), address(model));

        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new LendingPool(address(usdc), address(eth), address(rwa), address(oracle), address(0));
    }

    // ----- Montants trop petits -----
    // Après un an d'intérêts, une part et une unité de dette normalisée valent plus d'une unité
    // de tUSDC. Un montant d'une seule unité s'arrondirait à zéro : il est rejeté plutôt que
    // d'être encaissé sans contrepartie.

    function test_Deposit_RevertWhen_TooSmallToMintAShare() public {
        _openFungiblePosition();
        vm.warp(START + 365 days);

        vm.prank(lender);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.deposit(1);
    }

    function test_Repay_RevertWhen_TooSmallToReduceTheDebt() public {
        _openFungiblePosition();
        vm.warp(START + 365 days);

        vm.prank(borrower);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.repay(1);
    }

    function test_Liquidate_RevertWhen_TooSmallToReduceTheDebt() public {
        _openFungiblePosition();
        vm.warp(START + 365 days);
        _setEthPrice(1_800e18);
        vm.prank(admin);
        oracle.setPrice(address(usdc), USDC_PRICE);

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.liquidate(borrower, 1);
    }

    // ----- Garantie RWA -----

    function test_BorrowAgainstRwa_RevertWhen_PoolLacksLiquidity() public {
        _deposit(lender, 10_000 * USDC);
        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        vm.expectRevert(LendingPool.InsufficientLiquidity.selector);
        pool.borrowAgainstRwa(tokenId, 10_000 * USDC + 1);
        vm.stopPrank();
    }

    function test_BorrowAgainstRwa_RevertWhen_AmountIsZero() public {
        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.borrowAgainstRwa(tokenId, 0);
        vm.stopPrank();
    }

    function test_RepayRwa_RevertWhen_NoDebt() public {
        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        vm.expectRevert(LendingPool.NoDebt.selector);
        pool.repayRwa(tokenId, 1 * USDC);
        vm.stopPrank();
    }

    function test_GetRwaPosition_IsEmptyForUnknownToken() public view {
        LendingPool.RwaPositionInfo memory p = pool.getRwaPosition(999);
        assertEq(p.owner, address(0));
        assertEq(p.debt, 0);
        assertEq(p.buyoutPrice, 0);
    }

    // ----- Oracle sans prix -----

    /// @dev Les lectures destinées à l'interface ne rejettent jamais : sans prix, elles renvoient
    ///      des valeurs nulles et signalent que les prix ne sont pas valides. Les opérations qui
    ///      dépendent d'un prix, elles, sont rejetées.
    function test_Views_DoNotRevertWhenOracleHasNoPrice() public {
        vm.startPrank(admin);
        PriceOracle emptyOracle = new PriceOracle(admin, address(rwa), 30 days, 365 days);
        LendingPool pool2 =
            new LendingPool(address(usdc), address(eth), address(rwa), address(emptyOracle), address(model));
        vm.stopPrank();

        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        vm.startPrank(lender);
        usdc.approve(address(pool2), type(uint256).max);
        pool2.deposit(1_000 * USDC);
        vm.stopPrank();

        vm.startPrank(borrower);
        eth.approve(address(pool2), type(uint256).max);
        rwa.approve(address(pool2), tokenId);
        pool2.depositCollateral(1 * ETH);
        pool2.depositRwa(tokenId);
        vm.stopPrank();

        LendingPool.PoolState memory s = pool2.getPoolState();
        assertFalse(s.pricesValid);
        assertEq(s.assetPrice, 0);
        assertEq(s.collateralPrice, 0);
        assertEq(s.totalLiquidity, 1_000 * USDC);

        LendingPool.AccountPosition memory a = pool2.getAccountPosition(borrower);
        assertEq(a.collateral, 1 * ETH);
        assertEq(a.collateralValue, 0);
        assertEq(a.availableToBorrow, 0);

        LendingPool.RwaPositionInfo memory r = pool2.getRwaPosition(tokenId);
        assertEq(r.owner, borrower);
        assertEq(r.appraisedValue, 100_000e18);
        assertEq(r.availableToBorrow, 0);
        assertEq(r.buyoutPrice, 0);

        (uint256 seized, uint256 bonusValue) = pool2.previewLiquidation(1_000 * USDC);
        assertEq(seized, 0);
        assertEq(bonusValue, 0);

        vm.prank(borrower);
        vm.expectPartialRevert(PriceOracle.PriceNotSet.selector);
        pool2.borrow(1 * USDC);

        vm.prank(borrower);
        vm.expectPartialRevert(PriceOracle.PriceNotSet.selector);
        pool2.borrowAgainstRwa(tokenId, 1 * USDC);
    }
}
