// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingPool} from "../src/LendingPool.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice Prêt de liquidité : EF-11 à EF-14, EF-05 pour les événements, et la part d'EF-02
///         qui sépare le capital versé des intérêts générés.
contract LendingPoolLenderTest is Fixture {
    // ----- Dépôt -----

    function test_Deposit_GivesSharesAndFundsThePool() public {
        vm.expectEmit(true, false, false, true, address(pool));
        emit LendingPool.Deposited(lender, 100_000 * USDC, 100_000 * USDC);
        _deposit(lender, 100_000 * USDC);

        assertEq(pool.sharesOf(lender), 100_000 * USDC);
        assertEq(pool.totalShares(), 100_000 * USDC);
        assertEq(pool.totalCash(), 100_000 * USDC);
        assertEq(pool.totalLiquidity(), 100_000 * USDC);
        assertEq(usdc.balanceOf(address(pool)), 100_000 * USDC);
        assertEq(pool.getAccountPosition(lender).deposited, 100_000 * USDC);
        assertEq(pool.principalOf(lender), 100_000 * USDC);
    }

    function test_Deposit_RevertWhen_AmountIsZero() public {
        vm.prank(lender);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.deposit(0);
    }

    function test_Deposit_AfterInterest_GivesFewerShares() public {
        _openFungiblePosition();
        vm.warp(START + 365 days);
        // Après un an, les 100 000 parts du premier prêteur valent 100 472,50 tUSDC.
        // Un dépôt de 10 047,25 tUSDC donne donc exactement 10 000 parts.
        vm.prank(admin);
        usdc.mint(stranger, 10_047_250_000);

        vm.prank(stranger);
        uint256 shares = pool.deposit(10_047_250_000);

        assertEq(shares, 10_000 * USDC);
        assertEq(pool.getAccountPosition(stranger).deposited, 10_047_250_000);
    }

    // ----- Retrait -----

    function test_Withdraw_Partial() public {
        _deposit(lender, 100_000 * USDC);
        uint256 balanceBefore = usdc.balanceOf(lender);

        vm.expectEmit(true, false, false, true, address(pool));
        emit LendingPool.Withdrawn(lender, 40_000 * USDC, 40_000 * USDC);
        vm.prank(lender);
        uint256 withdrawn = pool.withdraw(40_000 * USDC);

        assertEq(withdrawn, 40_000 * USDC);
        assertEq(usdc.balanceOf(lender) - balanceBefore, 40_000 * USDC);
        assertEq(pool.sharesOf(lender), 60_000 * USDC);
        assertEq(pool.principalOf(lender), 60_000 * USDC);
        assertEq(pool.totalCash(), 60_000 * USDC);
    }

    function test_Withdraw_Max_ReturnsWholeDeposit() public {
        _deposit(lender, 100_000 * USDC);

        vm.prank(lender);
        uint256 withdrawn = pool.withdraw(type(uint256).max);

        assertEq(withdrawn, 100_000 * USDC);
        assertEq(usdc.balanceOf(lender), 1_000_000 * USDC);
        assertEq(pool.sharesOf(lender), 0);
        assertEq(pool.principalOf(lender), 0);
        assertEq(pool.totalShares(), 0);
        assertEq(pool.totalCash(), 0);
    }

    /// @dev EF-12, EF-13 : les intérêts reviennent au prêteur sans transaction de sa part.
    ///      15 000 empruntés pendant un an à 3,5 % : 525 d'intérêts, dont 10 % pour la réserve.
    function test_Withdraw_ReturnsDepositPlusInterest() public {
        _openFungiblePosition();
        vm.warp(START + 365 days);

        // L'emprunteur rembourse tout : 15 000 de capital et 525 d'intérêts.
        vm.prank(admin);
        usdc.mint(borrower, 525 * USDC);
        vm.prank(borrower);
        uint256 repaid = pool.repay(type(uint256).max);
        assertEq(repaid, 15_525 * USDC);

        uint256 balanceBefore = usdc.balanceOf(lender);
        vm.prank(lender);
        uint256 withdrawn = pool.withdraw(type(uint256).max);

        // 100 000 + 525 x 90 % = 100 472,50
        assertEq(withdrawn, 100_472_500_000);
        assertEq(usdc.balanceOf(lender) - balanceBefore, 100_472_500_000);
        // Il ne reste dans le pool que la réserve : 525 x 10 % = 52,50
        assertEq(pool.totalReserves(), 52_500_000);
        assertEq(pool.totalCash(), 52_500_000);
        assertEq(pool.totalShares(), 0);
        // Tout est retiré : il ne reste ni capital ni intérêts dans la position.
        LendingPool.AccountPosition memory p = pool.getAccountPosition(lender);
        assertEq(p.deposited, 0);
        assertEq(p.principal, 0);
        assertEq(p.interestEarned, 0);
    }

    function test_Withdraw_RevertWhen_AmountIsZero() public {
        _deposit(lender, 100_000 * USDC);

        vm.prank(lender);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.withdraw(0);
    }

    function test_Withdraw_RevertWhen_NothingDeposited() public {
        _deposit(lender, 100_000 * USDC);

        vm.prank(stranger);
        vm.expectRevert(LendingPool.InsufficientBalance.selector);
        pool.withdraw(1 * USDC);
    }

    function test_Withdraw_RevertWhen_MoreThanDeposited() public {
        _deposit(lender, 100_000 * USDC);

        vm.prank(lender);
        vm.expectRevert(LendingPool.InsufficientBalance.selector);
        pool.withdraw(100_000 * USDC + 1);
    }

    /// @dev EF-14 : 15 000 sont prêtés, il reste 85 000 dans le pool.
    function test_Withdraw_RevertWhen_FundsAreLentOut() public {
        _openFungiblePosition();

        vm.prank(lender);
        vm.expectRevert(LendingPool.InsufficientLiquidity.selector);
        pool.withdraw(90_000 * USDC);

        // Le montant disponible, lui, peut être retiré.
        vm.prank(lender);
        pool.withdraw(85_000 * USDC);
        assertEq(pool.totalCash(), 0);
    }

    // ----- Capital et intérêts générés (EF-02) -----

    /// @dev La position sépare le capital versé des intérêts générés.
    ///      15 000 empruntés pendant un an à 3,5 % : 525 d'intérêts, dont 90 % pour le prêteur.
    function test_Position_SeparatesPrincipalFromInterest() public {
        _openFungiblePosition();

        LendingPool.AccountPosition memory p = pool.getAccountPosition(lender);
        assertEq(p.principal, 100_000 * USDC);
        assertEq(p.interestEarned, 0);
        assertEq(p.deposited, 100_000 * USDC);

        vm.warp(START + 365 days);

        p = pool.getAccountPosition(lender);
        assertEq(p.principal, 100_000 * USDC); // le capital ne change pas sans dépôt ni retrait
        assertEq(p.interestEarned, 472_500_000); // 525 x 90 % = 472,50
        assertEq(p.deposited, p.principal + p.interestEarned);
    }

    /// @dev Un deuxième dépôt s'ajoute au capital. Les intérêts déjà générés n'y entrent pas.
    function test_Deposit_Twice_AddsToPrincipal() public {
        _openFungiblePosition();
        vm.warp(START + 365 days);

        _deposit(lender, 10_000 * USDC);

        LendingPool.AccountPosition memory p = pool.getAccountPosition(lender);
        assertEq(p.principal, 110_000 * USDC);
        assertEq(p.interestEarned, 472_500_000);
        assertEq(p.deposited, 110_472_500_000);
    }

    /// @dev Un retrait reprend capital et intérêts dans la même proportion. Ici le prêteur retire
    ///      la moitié de la valeur de son dépôt (100 472,50) : il lui reste la moitié du capital
    ///      et la moitié des intérêts.
    function test_Withdraw_Partial_TakesPrincipalAndInterestInProportion() public {
        _openFungiblePosition();
        vm.warp(START + 365 days);

        vm.prank(lender);
        pool.withdraw(50_236_250_000);

        LendingPool.AccountPosition memory p = pool.getAccountPosition(lender);
        assertEq(pool.sharesOf(lender), 50_000 * USDC);
        assertEq(p.principal, 50_000 * USDC);
        assertEq(p.interestEarned, 236_250_000);
        assertEq(p.deposited, 50_236_250_000);
    }

    /// @dev Quel que soit le retrait, le capital restant suit la part de parts conservée,
    ///      à une unité près, et ne dépasse jamais ce qui a été versé.
    function testFuzz_Withdraw_PrincipalFollowsShares(uint256 amount) public {
        _openFungiblePosition();
        vm.warp(START + 200 days);
        amount = bound(amount, 1, 85_000 * USDC); // ce que le pool a de disponible

        uint256 sharesBefore = pool.sharesOf(lender);
        vm.prank(lender);
        pool.withdraw(amount);

        uint256 principal = pool.principalOf(lender);
        assertLe(principal, 100_000 * USDC);
        assertApproxEqAbs(principal, 100_000 * USDC * pool.sharesOf(lender) / sharesBefore, 1);
    }

    // ----- Robustesse -----

    /// @dev Un jeton envoyé directement au contrat ne change pas la valeur des parts.
    function test_DirectTransfer_DoesNotChangeShareValue() public {
        _deposit(lender, 100_000 * USDC);

        vm.prank(liquidator);
        usdc.transfer(address(pool), 1_000 * USDC);

        assertEq(usdc.balanceOf(address(pool)), 101_000 * USDC);
        assertEq(pool.totalLiquidity(), 100_000 * USDC);
        assertEq(pool.getAccountPosition(lender).deposited, 100_000 * USDC);
    }

    /// @dev Déposer puis retirer aussitôt ne rapporte jamais rien : l'arrondi est en faveur du pool.
    function testFuzz_DepositThenWithdraw_NeverReturnsMore(uint256 amount) public {
        amount = bound(amount, 2, 1_000_000 * USDC);
        _openFungiblePosition();
        vm.warp(START + 100 days); // la valeur d'une part n'est plus de 1

        vm.prank(admin);
        usdc.mint(stranger, amount);

        vm.startPrank(stranger);
        pool.deposit(amount);
        uint256 withdrawn = pool.withdraw(type(uint256).max);
        vm.stopPrank();

        assertLe(withdrawn, amount);
        assertLe(amount - withdrawn, 2);
        assertEq(pool.principalOf(stranger), 0);
    }
}
