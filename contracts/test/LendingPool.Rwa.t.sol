// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {LendingPool} from "../src/LendingPool.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice Garantie sous forme d'actif réel tokenisé : EF-39 à EF-47.
/// @dev Au départ de chaque test : 100 000 tUSDC dans le pool, et l'emprunteur détient un jeton
///      RWA (une maison) expertisé à 100 000 $. Limite d'emprunt : 50 000. Liquidable quand
///      la dette dépasse 60 % de la valeur expertisée.
contract LendingPoolRwaTest is Fixture {
    uint256 internal tokenId;

    function setUp() public override {
        super.setUp();
        _deposit(lender, 100_000 * USDC);
        tokenId = _mintRwa(borrower, 100_000e18);
    }

    function _depositRwaAndBorrow(uint256 amount) internal {
        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        pool.borrowAgainstRwa(tokenId, amount);
        vm.stopPrank();
    }

    function _appraise(uint256 newValue) internal {
        vm.prank(admin);
        rwa.updateAppraisal(tokenId, newValue, keccak256("expertise-2"));
    }

    // ----- Dépôt et reprise du jeton (EF-39, EF-46) -----

    function test_DepositRwa_MovesTokenAndOpensPosition() public {
        vm.expectEmit(true, true, false, false, address(pool));
        emit LendingPool.RwaDeposited(borrower, tokenId);
        vm.prank(borrower);
        pool.depositRwa(tokenId);

        assertEq(rwa.ownerOf(tokenId), address(pool));

        LendingPool.RwaPositionInfo memory p = pool.getRwaPosition(tokenId);
        assertEq(p.owner, borrower);
        assertEq(p.debt, 0);
        assertEq(p.appraisedValue, 100_000e18);
        assertEq(p.availableToBorrow, 50_000 * USDC);
        assertEq(p.healthFactor, type(uint256).max);

        uint256[] memory ids = pool.getRwaTokenIds();
        assertEq(ids.length, 1);
        assertEq(ids[0], tokenId);
    }

    /// @dev Le pool est approuvé par l'emprunteur, mais un tiers ne peut pas s'en servir pour
    ///      déposer le jeton d'un autre à son propre nom.
    function test_DepositRwa_RevertWhen_CallerDoesNotOwnToken() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, stranger, tokenId, borrower)
        );
        pool.depositRwa(tokenId);
    }

    function test_DepositRwa_RevertWhen_AlreadyDeposited() public {
        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        vm.expectRevert(LendingPool.RwaAlreadyDeposited.selector);
        pool.depositRwa(tokenId);
        vm.stopPrank();
    }

    function test_WithdrawRwa_WhenNoDebt() public {
        vm.startPrank(borrower);
        pool.depositRwa(tokenId);

        vm.expectEmit(true, true, false, false, address(pool));
        emit LendingPool.RwaWithdrawn(borrower, tokenId);
        pool.withdrawRwa(tokenId);
        vm.stopPrank();

        assertEq(rwa.ownerOf(tokenId), borrower);
        assertEq(pool.getRwaPosition(tokenId).owner, address(0));
        assertEq(pool.getRwaTokenIds().length, 0);
    }

    /// @dev EF-39 : le jeton se reprend une fois la dette entièrement remboursée.
    function test_WithdrawRwa_AfterFullRepayment() public {
        _depositRwaAndBorrow(30_000 * USDC);

        vm.startPrank(borrower);
        vm.expectEmit(true, true, false, true, address(pool));
        emit LendingPool.RwaRepaid(borrower, tokenId, 30_000 * USDC);
        uint256 repaid = pool.repayRwa(tokenId, type(uint256).max);
        pool.withdrawRwa(tokenId);
        vm.stopPrank();

        assertEq(repaid, 30_000 * USDC);
        assertEq(rwa.ownerOf(tokenId), borrower);
        assertEq(pool.totalBorrows(), 0);
        assertEq(pool.totalCash(), 100_000 * USDC);
    }

    /// @dev EF-46 : tant qu'une dette subsiste, le jeton reste en garantie.
    function test_WithdrawRwa_RevertWhen_DebtOutstanding() public {
        _depositRwaAndBorrow(30_000 * USDC);

        vm.startPrank(borrower);
        pool.repayRwa(tokenId, 29_999 * USDC);
        vm.expectRevert(LendingPool.DebtOutstanding.selector);
        pool.withdrawRwa(tokenId);
        vm.stopPrank();
    }

    function test_WithdrawRwa_RevertWhen_CallerIsNotPositionOwner() public {
        vm.prank(borrower);
        pool.depositRwa(tokenId);

        vm.prank(stranger);
        vm.expectRevert(LendingPool.NotPositionOwner.selector);
        pool.withdrawRwa(tokenId);
    }

    // ----- Emprunt (EF-40, EF-41) -----

    /// @dev EF-41 : 50 % de 100 000 $ = 50 000 tUSDC.
    function test_BorrowAgainstRwa_UpToHalfTheAppraisedValue() public {
        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        vm.expectEmit(true, true, false, true, address(pool));
        emit LendingPool.RwaBorrowed(borrower, tokenId, 50_000 * USDC);
        pool.borrowAgainstRwa(tokenId, 50_000 * USDC);
        vm.stopPrank();

        assertEq(usdc.balanceOf(borrower), 50_000 * USDC);
        assertEq(pool.totalCash(), 50_000 * USDC);
        assertEq(pool.totalBorrows(), 50_000 * USDC);
        // 100 000 x 60 % / 50 000 = 1,2 : une position ouverte à la limite n'est pas liquidable
        assertEq(pool.rwaHealthFactor(tokenId), 1.2e18);
    }

    function test_BorrowAgainstRwa_RevertWhen_AboveLtv() public {
        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        vm.expectRevert(LendingPool.ExceedsBorrowLimit.selector);
        pool.borrowAgainstRwa(tokenId, 50_000 * USDC + 1);
        vm.stopPrank();
    }

    /// @dev EF-40 : une expertise de plus d'un an est périmée et ne permet plus d'emprunter.
    function test_BorrowAgainstRwa_RevertWhen_AppraisalIsStale() public {
        vm.prank(borrower);
        pool.depositRwa(tokenId);

        vm.warp(START + 365 days + 1);
        _refreshPrices();

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.StaleAppraisal.selector, tokenId, START));
        pool.borrowAgainstRwa(tokenId, 10_000 * USDC);

        LendingPool.RwaPositionInfo memory p = pool.getRwaPosition(tokenId);
        assertFalse(p.appraisalValid);
        assertEq(p.availableToBorrow, 0);

        // Une nouvelle expertise rend l'emprunt de nouveau possible.
        _appraise(100_000e18);
        vm.prank(borrower);
        pool.borrowAgainstRwa(tokenId, 10_000 * USDC);
    }

    function test_BorrowAgainstRwa_RevertWhen_CallerIsNotPositionOwner() public {
        vm.prank(borrower);
        pool.depositRwa(tokenId);

        vm.prank(stranger);
        vm.expectRevert(LendingPool.NotPositionOwner.selector);
        pool.borrowAgainstRwa(tokenId, 1_000 * USDC);
    }

    function test_BorrowAgainstRwa_RevertWhen_TokenIsNotDeposited() public {
        vm.prank(borrower);
        vm.expectRevert(LendingPool.NotPositionOwner.selector);
        pool.borrowAgainstRwa(tokenId, 1_000 * USDC);
    }

    function test_RepayRwa_Partial() public {
        _depositRwaAndBorrow(30_000 * USDC);

        vm.prank(borrower);
        uint256 repaid = pool.repayRwa(tokenId, 10_000 * USDC);

        assertEq(repaid, 10_000 * USDC);
        assertEq(pool.getRwaPosition(tokenId).debt, 20_000 * USDC);
    }

    function test_RepayRwa_RevertWhen_CallerIsNotPositionOwner() public {
        _depositRwaAndBorrow(30_000 * USDC);

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.NotPositionOwner.selector);
        pool.repayRwa(tokenId, 1_000 * USDC);
    }

    // ----- Position affichée (EF-47) -----

    function test_GetRwaPosition() public {
        _depositRwaAndBorrow(30_000 * USDC);

        LendingPool.RwaPositionInfo memory p = pool.getRwaPosition(tokenId);
        assertEq(p.owner, borrower);
        assertEq(p.debt, 30_000 * USDC);
        assertEq(p.debtValue, 30_000e18);
        assertEq(p.appraisedValue, 100_000e18);
        assertEq(p.appraisedAt, START);
        assertTrue(p.appraisalValid);
        assertEq(p.availableToBorrow, 20_000 * USDC); // 50 000 - 30 000
        assertEq(p.healthFactor, 2e18); // 100 000 x 60 % / 30 000
        assertEq(p.buyoutPrice, 95_000 * USDC); // 100 000 moins 5 %
        assertEq(p.liquidatorGain, 5_000e18);
        assertFalse(p.liquidatable);
    }

    /// @dev Chaque jeton a sa propre dette : la chute de tETH n'affecte pas la position RWA.
    function test_RwaPosition_IsIndependentFromFungiblePosition() public {
        _depositRwaAndBorrow(50_000 * USDC);
        _depositCollateral(borrower, 10 * ETH);
        _borrow(borrower, 15_000 * USDC);

        _setEthPrice(1_000e18);

        assertTrue(pool.getAccountPosition(borrower).liquidatable);
        assertEq(pool.getAccountPosition(borrower).debt, 15_000 * USDC);
        assertEq(pool.rwaHealthFactor(tokenId), 1.2e18);
        assertFalse(pool.getRwaPosition(tokenId).liquidatable);
    }

    // ----- Rachat de la garantie (EF-42 à EF-46) -----

    /// @dev EF-46 : une position RWA saine ne peut pas être rachetée.
    function test_BuyoutRwa_RevertWhen_PositionIsHealthy() public {
        _depositRwaAndBorrow(50_000 * USDC);

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.PositionHealthy.selector);
        pool.buyoutRwa(tokenId);
    }

    function test_BuyoutRwa_RevertWhen_PositionHasNoDebt() public {
        vm.prank(borrower);
        pool.depositRwa(tokenId);
        _appraise(1e18); // même une valeur infime ne rend pas liquidable une position sans dette

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.PositionHealthy.selector);
        pool.buyoutRwa(tokenId);
    }

    function test_BuyoutRwa_RevertWhen_TokenIsNotDeposited() public {
        vm.prank(liquidator);
        vm.expectRevert(LendingPool.NoRwaPosition.selector);
        pool.buyoutRwa(tokenId);
    }

    /// @dev EF-42 à EF-44. Nouvelle expertise à 80 000 $ : facteur de santé = 80 000 x 60 % / 50 000 = 0,96.
    ///      Le liquidateur verse 80 000 moins 5 % = 76 000. Le pool récupère les 50 000 de dette,
    ///      l'emprunteur reçoit le solde de 26 000, et le liquidateur reçoit le jeton.
    function test_BuyoutRwa_RepaysPoolRefundsBorrowerAndTransfersToken() public {
        _depositRwaAndBorrow(50_000 * USDC);
        _appraise(80_000e18);

        assertEq(pool.rwaHealthFactor(tokenId), 0.96e18);
        LendingPool.RwaPositionInfo memory p = pool.getRwaPosition(tokenId);
        assertTrue(p.liquidatable);
        assertEq(p.buyoutPrice, 76_000 * USDC);
        assertEq(p.liquidatorGain, 4_000e18);

        uint256 liquidatorBefore = usdc.balanceOf(liquidator);
        vm.expectEmit(true, true, true, true, address(pool));
        emit LendingPool.RwaBoughtOut(liquidator, borrower, tokenId, 76_000 * USDC, 50_000 * USDC, 26_000 * USDC, 0);
        vm.prank(liquidator);
        uint256 price = pool.buyoutRwa(tokenId);

        assertEq(price, 76_000 * USDC);
        assertEq(liquidatorBefore - usdc.balanceOf(liquidator), 76_000 * USDC);
        assertEq(rwa.ownerOf(tokenId), liquidator);
        assertEq(usdc.balanceOf(borrower), 76_000 * USDC); // 50 000 empruntés + 26 000 de solde

        assertEq(pool.totalCash(), 100_000 * USDC);
        assertEq(pool.totalBorrows(), 0);
        assertEq(usdc.balanceOf(address(pool)), 100_000 * USDC);
        assertEq(pool.getRwaPosition(tokenId).owner, address(0));
        assertEq(pool.getRwaTokenIds().length, 0);
    }

    /// @dev EF-45. Après un an à 7 %, la dette est de 53 500 et la réserve de 350.
    ///      Expertise à 56 000 $ : le rachat rapporte 53 200, il manque 300. La réserve absorbe
    ///      l'écart et les fonds des prêteurs ne changent pas.
    function test_BuyoutRwa_ShortfallIsChargedToTheReserve() public {
        _depositRwaAndBorrow(50_000 * USDC);
        vm.warp(START + 365 days);
        _refreshPrices();
        pool.accrueInterest();
        assertEq(pool.getRwaPosition(tokenId).debt, 53_500 * USDC);
        assertEq(pool.totalReserves(), 350 * USDC);
        assertEq(pool.totalLiquidity(), 103_150 * USDC);

        _appraise(56_000e18);
        vm.expectEmit(true, true, true, true, address(pool));
        emit LendingPool.RwaBoughtOut(liquidator, borrower, tokenId, 53_200 * USDC, 53_200 * USDC, 0, 300 * USDC);
        vm.prank(liquidator);
        pool.buyoutRwa(tokenId);

        assertEq(pool.totalReserves(), 50 * USDC);
        assertEq(pool.totalBorrows(), 0);
        assertEq(pool.totalLiquidity(), 103_150 * USDC);
        assertEq(usdc.balanceOf(borrower), 50_000 * USDC); // aucun solde à lui remettre
        assertEq(rwa.ownerOf(tokenId), liquidator);
    }

    /// @dev Si la réserve ne suffit pas, elle tombe à zéro et le reste de la perte est supporté
    ///      par les prêteurs. Expertise à 50 000 $ : rachat à 47 500, il manque 6 000.
    function test_BuyoutRwa_ShortfallBeyondTheReserveIsBorneByLenders() public {
        _depositRwaAndBorrow(50_000 * USDC);
        vm.warp(START + 365 days);
        _refreshPrices();

        _appraise(50_000e18);
        vm.prank(liquidator);
        uint256 price = pool.buyoutRwa(tokenId);

        assertEq(price, 47_500 * USDC);
        assertEq(pool.totalReserves(), 0);
        assertEq(pool.totalLiquidity(), 97_500 * USDC);

        // Le prêteur a perdu 2 500 : son dépôt vaut moins que le capital versé, et ses
        // intérêts générés restent à zéro au lieu de devenir négatifs (EF-02).
        LendingPool.AccountPosition memory p = pool.getAccountPosition(lender);
        assertEq(p.deposited, 97_500 * USDC);
        assertEq(p.principal, 100_000 * USDC);
        assertEq(p.interestEarned, 0);
    }

    function test_BuyoutRwa_RevertWhen_LiquidatorLacksFunds() public {
        _depositRwaAndBorrow(50_000 * USDC);
        _appraise(80_000e18);

        vm.prank(stranger); // n'a aucun tUSDC
        vm.expectRevert();
        pool.buyoutRwa(tokenId);
    }

    function test_BuyoutRwa_RevertWhen_AppraisalIsStale() public {
        _depositRwaAndBorrow(50_000 * USDC);
        vm.warp(START + 365 days + 1);
        _refreshPrices();

        vm.prank(liquidator);
        vm.expectPartialRevert(PriceOracle.StaleAppraisal.selector);
        pool.buyoutRwa(tokenId);
    }
}
