// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingPool} from "../src/LendingPool.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice Emprunt, garantie fongible et intérêts : EF-16 à EF-21, EF-25, EF-29.
/// @dev Au départ de chaque test : 100 000 tUSDC dans le pool, et l'emprunteur a déposé
///      10 tETH de garantie, soit 20 000 $. Sa limite d'emprunt est donc de 15 000 tUSDC.
contract LendingPoolBorrowTest is Fixture {
    function setUp() public override {
        super.setUp();
        _deposit(lender, 100_000 * USDC);
        _depositCollateral(borrower, 10 * ETH);
    }

    // ----- Garantie -----

    /// @dev EF-16 : la garantie n'est pas un dépôt de prêteur.
    function test_DepositCollateral_IsSeparateFromLenderDeposit() public view {
        assertEq(pool.collateralOf(borrower), 10 * ETH);
        assertEq(eth.balanceOf(address(pool)), 10 * ETH);

        assertEq(pool.sharesOf(borrower), 0);
        assertEq(pool.getAccountPosition(borrower).deposited, 0);
        assertEq(pool.totalLiquidity(), 100_000 * USDC);
    }

    function test_DepositCollateral_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(pool));
        emit LendingPool.CollateralDeposited(borrower, 5 * ETH);
        _depositCollateral(borrower, 5 * ETH);

        assertEq(pool.collateralOf(borrower), 15 * ETH);
    }

    function test_DepositCollateral_RevertWhen_AmountIsZero() public {
        vm.prank(borrower);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.depositCollateral(0);
    }

    function test_WithdrawCollateral_WhenNoDebt() public {
        vm.expectEmit(true, false, false, true, address(pool));
        emit LendingPool.CollateralWithdrawn(borrower, 10 * ETH);
        vm.prank(borrower);
        pool.withdrawCollateral(10 * ETH);

        assertEq(pool.collateralOf(borrower), 0);
        assertEq(eth.balanceOf(borrower), 100 * ETH);
    }

    /// @dev EF-21 : avec 8 000 de dette, il faut garder 5 tETH (10 000 $ x 80 % = 8 000).
    function test_WithdrawCollateral_OnlyWhilePositionStaysHealthy() public {
        _borrow(borrower, 8_000 * USDC);

        // Retirer 5 tETH laisse un facteur de santé d'exactement 1 : accepté.
        vm.prank(borrower);
        pool.withdrawCollateral(5 * ETH);
        assertEq(pool.healthFactor(borrower), 1e18);

        // Retirer la plus petite unité de plus le ferait passer sous 1 : refusé.
        vm.prank(borrower);
        vm.expectRevert(LendingPool.HealthFactorTooLow.selector);
        pool.withdrawCollateral(1);
    }

    function test_WithdrawCollateral_RevertWhen_MoreThanDeposited() public {
        vm.prank(borrower);
        vm.expectRevert(LendingPool.InsufficientCollateral.selector);
        pool.withdrawCollateral(10 * ETH + 1);
    }

    // ----- Emprunt -----

    /// @dev EF-17 : 75 % de 20 000 $ = 15 000 tUSDC.
    function test_Borrow_UpToLtv() public {
        vm.expectEmit(true, false, false, true, address(pool));
        emit LendingPool.Borrowed(borrower, 15_000 * USDC);
        _borrow(borrower, 15_000 * USDC);

        assertEq(usdc.balanceOf(borrower), 15_000 * USDC);
        assertEq(pool.totalCash(), 85_000 * USDC);
        assertEq(pool.totalBorrows(), 15_000 * USDC);

        LendingPool.AccountPosition memory p = pool.getAccountPosition(borrower);
        assertEq(p.debt, 15_000 * USDC);
        assertEq(p.availableToBorrow, 0);
        // 20 000 x 80 % / 15 000 = 1,0666... : une position ouverte à la limite n'est pas liquidable
        assertEq(p.healthFactor, 1066666666666666666);
        assertFalse(p.liquidatable);
    }

    /// @dev EF-18 : un emprunt au-delà de la limite est rejeté, même d'une seule unité.
    function test_Borrow_RevertWhen_AboveLtv() public {
        vm.prank(borrower);
        vm.expectRevert(LendingPool.ExceedsBorrowLimit.selector);
        pool.borrow(15_000 * USDC + 1);
    }

    function test_Borrow_RevertWhen_AboveLtvInTwoSteps() public {
        _borrow(borrower, 10_000 * USDC);

        vm.prank(borrower);
        vm.expectRevert(LendingPool.ExceedsBorrowLimit.selector);
        pool.borrow(5_000 * USDC + 1);
    }

    function test_Borrow_RevertWhen_NoCollateral() public {
        vm.prank(stranger);
        vm.expectRevert(LendingPool.ExceedsBorrowLimit.selector);
        pool.borrow(1 * USDC);
    }

    function test_Borrow_RevertWhen_AmountIsZero() public {
        vm.prank(borrower);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.borrow(0);
    }

    function test_Borrow_RevertWhen_PoolLacksLiquidity() public {
        // 100 tETH de garantie autorisent 150 000, mais le pool n'a que 100 000.
        _depositCollateral(borrower, 90 * ETH);

        vm.prank(borrower);
        vm.expectRevert(LendingPool.InsufficientLiquidity.selector);
        pool.borrow(100_000 * USDC + 1);

        // Le montant empruntable affiché est plafonné par la liquidité du pool.
        assertEq(pool.getAccountPosition(borrower).availableToBorrow, 100_000 * USDC);
    }

    /// @dev EF-25 : les taux suivent le taux d'utilisation après chaque opération.
    function test_Borrow_UpdatesUtilizationAndRates() public {
        _depositCollateral(borrower, 20 * ETH); // 30 tETH au total, limite de 45 000
        _borrow(borrower, 40_000 * USDC);

        LendingPool.PoolState memory s = pool.getPoolState();
        assertEq(s.totalLiquidity, 100_000 * USDC);
        assertEq(s.availableLiquidity, 60_000 * USDC);
        assertEq(s.totalBorrows, 40_000 * USDC);
        assertEq(s.totalReserves, 0);
        assertEq(s.utilization, 0.4e18);
        assertEq(s.borrowRate, 0.06e18);
        assertEq(s.supplyRate, 0.0216e18);
        assertEq(s.assetPrice, USDC_PRICE);
        assertEq(s.collateralPrice, ETH_PRICE);
        assertTrue(s.pricesValid);
    }

    function test_GetBorrowers_TracksOpenDebts() public {
        assertEq(pool.getBorrowers().length, 0);

        _borrow(borrower, 5_000 * USDC);
        _borrow(borrower, 1_000 * USDC); // un second emprunt n'ajoute pas de doublon
        address[] memory list = pool.getBorrowers();
        assertEq(list.length, 1);
        assertEq(list[0], borrower);

        vm.prank(borrower);
        pool.repay(type(uint256).max);
        assertEq(pool.getBorrowers().length, 0);
    }

    // ----- Position affichée (EF-02, EF-03, EF-18) -----

    function test_GetAccountPosition() public {
        _borrow(borrower, 8_000 * USDC);

        LendingPool.AccountPosition memory p = pool.getAccountPosition(borrower);
        assertEq(p.deposited, 0);
        assertEq(p.collateral, 10 * ETH);
        assertEq(p.debt, 8_000 * USDC);
        assertEq(p.collateralValue, 20_000e18);
        assertEq(p.debtValue, 8_000e18);
        assertEq(p.availableToBorrow, 7_000 * USDC); // 15 000 - 8 000
        assertEq(p.healthFactor, 2e18); // 20 000 x 80 % / 8 000
        assertEq(p.liquidationPrice, 1_000e18); // 8 000 / (10 x 80 %)
        assertEq(p.maxLiquidationRepay, 0);
        assertFalse(p.liquidatable);
    }

    function test_HealthFactor_IsMaxWithoutDebt() public view {
        assertEq(pool.healthFactor(borrower), type(uint256).max);
        assertEq(pool.getAccountPosition(borrower).liquidationPrice, 0);
    }

    // ----- Remboursement (EF-20) -----

    function test_Repay_Partial() public {
        _borrow(borrower, 15_000 * USDC);

        vm.expectEmit(true, false, false, true, address(pool));
        emit LendingPool.Repaid(borrower, 5_000 * USDC);
        vm.prank(borrower);
        uint256 repaid = pool.repay(5_000 * USDC);

        assertEq(repaid, 5_000 * USDC);
        assertEq(pool.getAccountPosition(borrower).debt, 10_000 * USDC);
        assertEq(pool.totalCash(), 90_000 * USDC);
        assertEq(usdc.balanceOf(borrower), 10_000 * USDC);
    }

    function test_Repay_MoreThanDebt_OnlyTakesTheDebt() public {
        _borrow(borrower, 15_000 * USDC);
        vm.prank(admin);
        usdc.mint(borrower, 5_000 * USDC);

        vm.prank(borrower);
        uint256 repaid = pool.repay(20_000 * USDC);

        assertEq(repaid, 15_000 * USDC);
        assertEq(pool.getAccountPosition(borrower).debt, 0);
        assertEq(pool.totalBorrows(), 0);
        assertEq(usdc.balanceOf(borrower), 5_000 * USDC);
    }

    function test_Repay_RevertWhen_NoDebt() public {
        vm.prank(borrower);
        vm.expectRevert(LendingPool.NoDebt.selector);
        pool.repay(1 * USDC);
    }

    function test_Repay_RevertWhen_AmountIsZero() public {
        _borrow(borrower, 15_000 * USDC);

        vm.prank(borrower);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.repay(0);
    }

    // ----- Intérêts (EF-25) -----

    /// @dev 15 000 empruntés sur 100 000 : U = 15 %, taux = 2 % + 8 % x 15/80 = 3,5 %.
    ///      Sur un an : 525 d'intérêts, dont 52,50 pour la réserve.
    function test_Interest_AccruesWithTime() public {
        _borrow(borrower, 15_000 * USDC);
        vm.warp(START + 365 days);

        // Les lectures comptent déjà les intérêts, avant toute transaction.
        assertEq(pool.totalBorrows(), 15_525 * USDC);
        assertEq(pool.getAccountPosition(borrower).debt, 15_525 * USDC);
        assertEq(pool.getAccountPosition(lender).deposited, 100_472_500_000);
        assertEq(pool.borrowIndex(), 1e18); // l'état n'est pas encore écrit

        vm.expectEmit(false, false, false, true, address(pool));
        emit LendingPool.InterestAccrued(1.035e18, 15_525 * USDC, 52_500_000);
        pool.accrueInterest();

        assertEq(pool.borrowIndex(), 1.035e18);
        assertEq(pool.totalReserves(), 52_500_000);
        assertEq(pool.lastAccrual(), START + 365 days);
        assertEq(pool.totalBorrows(), 15_525 * USDC);
    }

    /// @dev Les intérêts se composent : deux calculs de six mois donnent plus qu'un seul d'un an.
    function test_Interest_CompoundsBetweenOperations() public {
        _borrow(borrower, 15_000 * USDC);

        vm.warp(START + 365 days / 2);
        pool.accrueInterest();
        assertEq(pool.borrowIndex(), 1.0175e18);

        vm.warp(START + 365 days);
        pool.accrueInterest();
        assertGt(pool.borrowIndex(), 1.035e18);
    }

    /// @dev Le temps passé sans aucun emprunt n'est pas facturé au premier emprunteur.
    function test_Interest_IdleTimeBeforeFirstBorrowIsNotCharged() public {
        vm.warp(START + 200 days);
        _refreshPrices();
        _borrow(borrower, 15_000 * USDC);

        assertEq(pool.borrowIndex(), 1e18);
        assertEq(pool.getAccountPosition(borrower).debt, 15_000 * USDC);

        // Un jour plus tard, la dette porte un jour d'intérêts : 15 000 x 3,5 % / 365 = 1,438356
        vm.warp(START + 201 days);
        assertApproxEqAbs(pool.getAccountPosition(borrower).debt, 15_001_438_357, 1);
    }

    // ----- Prix périmé (EF-29) -----

    /// @dev Une opération qui dépend d'un prix périmé est rejetée. Rembourser ou retirer son
    ///      dépôt n'en dépend pas et reste possible.
    function test_StalePrice_BlocksBorrowButNotRepayOrWithdraw() public {
        _borrow(borrower, 10_000 * USDC);
        vm.warp(START + 30 days + 1);

        vm.prank(borrower);
        vm.expectPartialRevert(PriceOracle.StalePrice.selector);
        pool.borrow(1 * USDC);

        vm.prank(borrower);
        vm.expectPartialRevert(PriceOracle.StalePrice.selector);
        pool.withdrawCollateral(1 * ETH);

        assertFalse(pool.getPoolState().pricesValid);

        vm.prank(borrower);
        pool.repay(1_000 * USDC);
        vm.prank(lender);
        pool.withdraw(1_000 * USDC);
    }
}
