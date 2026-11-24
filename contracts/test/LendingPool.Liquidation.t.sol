// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {LendingPool} from "../src/LendingPool.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice Facteur de santé et liquidation d'une position à garantie fongible : EF-30 à EF-36.
/// @dev Au départ de chaque test : 10 tETH de garantie (20 000 $) et 15 000 tUSDC de dette.
///      La position devient liquidable quand tETH passe sous 1 875 $ : 15 000 / (10 x 80 %).
contract LendingPoolLiquidationTest is Fixture {
    function setUp() public override {
        super.setUp();
        _openFungiblePosition();
    }

    // ----- Facteur de santé (EF-30, EF-31) -----

    function test_HealthFactor_FollowsCollateralPrice() public {
        assertEq(pool.healthFactor(borrower), 1066666666666666666); // 20 000 x 80 % / 15 000

        _setEthPrice(1_800e18);
        assertEq(pool.healthFactor(borrower), 0.96e18); // 18 000 x 80 % / 15 000

        LendingPool.AccountPosition memory p = pool.getAccountPosition(borrower);
        assertTrue(p.liquidatable);
        assertEq(p.maxLiquidationRepay, 7_500 * USDC); // 50 % de la dette
    }

    /// @dev EF-03 : le prix de liquidation affiché est bien celui où le facteur de santé vaut 1.
    function test_LiquidationPrice_IsWhereHealthFactorReachesOne() public {
        assertEq(pool.getAccountPosition(borrower).liquidationPrice, 1_875e18);

        _setEthPrice(1_875e18);
        assertEq(pool.healthFactor(borrower), 1e18);
        assertFalse(pool.getAccountPosition(borrower).liquidatable);

        _setEthPrice(1_874e18);
        assertLt(pool.healthFactor(borrower), 1e18);
        assertTrue(pool.getAccountPosition(borrower).liquidatable);
    }

    // ----- Liquidation (EF-32 à EF-34) -----

    /// @dev tETH à 1 800 $. Le liquidateur rembourse 7 500 et reçoit 7 500 x 1,05 / 1 800 = 4,375 tETH,
    ///      qui valent 7 875 $ : son gain est de 375 $, soit 5 %.
    function test_Liquidate_RepaysHalfTheDebtAndSeizesCollateralWithBonus() public {
        _setEthPrice(1_800e18);
        uint256 usdcBefore = usdc.balanceOf(liquidator);

        vm.expectEmit(true, true, false, true, address(pool));
        emit LendingPool.Liquidated(liquidator, borrower, 7_500 * USDC, 4.375e18);
        vm.prank(liquidator);
        uint256 seized = pool.liquidate(borrower, 7_500 * USDC);

        // Le liquidateur a payé 7 500 tUSDC et reçu 4,375 tETH.
        assertEq(seized, 4.375e18);
        assertEq(eth.balanceOf(liquidator), 4.375e18);
        assertEq(usdcBefore - usdc.balanceOf(liquidator), 7_500 * USDC);

        // La position est mise à jour dans la même transaction, et redevient saine.
        LendingPool.AccountPosition memory p = pool.getAccountPosition(borrower);
        assertEq(p.debt, 7_500 * USDC);
        assertEq(p.collateral, 5.625e18);
        assertEq(p.healthFactor, 1.08e18); // 10 125 x 80 % / 7 500
        assertFalse(p.liquidatable);

        // Le pool a récupéré les fonds remboursés.
        assertEq(pool.totalCash(), 92_500 * USDC);
        assertEq(pool.totalBorrows(), 7_500 * USDC);
        assertEq(eth.balanceOf(address(pool)), 5.625e18);
    }

    function test_Liquidate_ByAnyUser() public {
        _setEthPrice(1_800e18);
        vm.prank(admin);
        usdc.mint(stranger, 1_000 * USDC);

        vm.prank(stranger);
        pool.liquidate(borrower, 1_000 * USDC);

        assertEq(pool.getAccountPosition(borrower).debt, 14_000 * USDC);
        assertGt(eth.balanceOf(stranger), 0);
    }

    /// @dev Tant que la position reste sous 1, elle peut être liquidée de nouveau.
    ///      À 1 500 $, la garantie (15 000 $) ne couvre plus la dette majorée du bonus.
    function test_Liquidate_AgainWhileStillUnhealthy() public {
        _setEthPrice(1_500e18);

        vm.startPrank(liquidator);
        assertEq(pool.liquidate(borrower, 7_500 * USDC), 5.25e18);
        assertEq(pool.healthFactor(borrower), 0.76e18); // 4,75 x 1 500 x 80 % / 7 500

        assertEq(pool.liquidate(borrower, 3_750 * USDC), 2.625e18);
        vm.stopPrank();

        LendingPool.AccountPosition memory p = pool.getAccountPosition(borrower);
        assertEq(p.debt, 3_750 * USDC);
        assertEq(p.collateral, 2.125e18);
    }

    function test_PreviewLiquidation() public {
        _setEthPrice(1_800e18);

        (uint256 seized, uint256 bonusValue) = pool.previewLiquidation(7_500 * USDC);
        assertEq(seized, 4.375e18);
        assertEq(bonusValue, 375e18); // gain estimé du liquidateur, en USD
    }

    // ----- Rejets (EF-33, EF-35) -----

    function test_Liquidate_RevertWhen_PositionIsHealthy() public {
        vm.prank(liquidator);
        vm.expectRevert(LendingPool.PositionHealthy.selector);
        pool.liquidate(borrower, 7_500 * USDC);
    }

    function test_Liquidate_RevertWhen_AboveCloseFactor() public {
        _setEthPrice(1_800e18);

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.ExceedsCloseFactor.selector);
        pool.liquidate(borrower, 7_500 * USDC + 1);
    }

    function test_Liquidate_RevertWhen_LiquidatorLacksFunds() public {
        _setEthPrice(1_800e18);

        vm.prank(stranger); // n'a aucun tUSDC
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, 7_500 * USDC)
        );
        pool.liquidate(borrower, 7_500 * USDC);
    }

    /// @dev À 700 $, rembourser 7 500 donnerait droit à 11,25 tETH : plus que les 10 déposés.
    function test_Liquidate_RevertWhen_SeizeExceedsCollateral() public {
        _setEthPrice(700e18);

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.InsufficientCollateral.selector);
        pool.liquidate(borrower, 7_500 * USDC);

        // Un montant plus petit, couvert par la garantie, reste possible.
        vm.prank(liquidator);
        pool.liquidate(borrower, 6_000 * USDC);
        assertEq(pool.getAccountPosition(borrower).collateral, 1 * ETH); // 10 - 6 000 x 1,05 / 700
    }

    function test_Liquidate_RevertWhen_BorrowerHasNoDebt() public {
        vm.prank(liquidator);
        vm.expectRevert(LendingPool.NoDebt.selector);
        pool.liquidate(stranger, 1_000 * USDC);
    }

    function test_Liquidate_RevertWhen_AmountIsZero() public {
        _setEthPrice(1_800e18);

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.liquidate(borrower, 0);
    }

    /// @dev EF-29 : une liquidation qui repose sur un prix périmé est rejetée, même si la position
    ///      était liquidable au dernier prix connu. Elle redevient possible dès que les prix sont réinscrits.
    function test_Liquidate_RevertWhen_PriceIsStale() public {
        _setEthPrice(1_800e18);
        vm.warp(START + 30 days + 1);

        vm.prank(liquidator);
        vm.expectPartialRevert(PriceOracle.StalePrice.selector);
        pool.liquidate(borrower, 1_000 * USDC);

        vm.startPrank(admin);
        oracle.setPrice(address(eth), 1_800e18);
        oracle.setPrice(address(usdc), USDC_PRICE);
        vm.stopPrank();

        vm.prank(liquidator);
        pool.liquidate(borrower, 1_000 * USDC);
        assertGt(eth.balanceOf(liquidator), 0);
    }

    /// @dev Quel que soit le prix et le montant, une liquidation acceptée ne prend jamais plus de
    ///      garantie que la valeur remboursée majorée de 5 %, et ne dépasse jamais 50 % de la dette.
    function testFuzz_Liquidate_RespectsBonusAndCloseFactor(uint256 price, uint256 repayAmount) public {
        price = bound(price, 800e18, 1_874e18); // sous le prix de liquidation
        repayAmount = bound(repayAmount, 1 * USDC, 7_500 * USDC);
        _setEthPrice(price);

        uint256 debtBefore = pool.getAccountPosition(borrower).debt;
        vm.prank(liquidator);
        uint256 seized = pool.liquidate(borrower, repayAmount);

        // valeur de la garantie reçue <= valeur remboursée x 1,05
        assertLe(seized * price / 1e18, repayAmount * 1e12 * 105 / 100);
        assertEq(pool.getAccountPosition(borrower).debt, debtBefore - repayAmount);
        assertEq(eth.balanceOf(liquidator), seized);
    }
}
