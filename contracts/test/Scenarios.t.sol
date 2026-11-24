// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";

import {LendingPool} from "../src/LendingPool.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice Les deux scénarios de la démonstration, joués de bout en bout.
///         Ils suivent les sections 3.2 et 3.3 de la proposition de projet.
/// @dev Chaque scénario raconte ce qu'il fait, avec les valeurs lues sur les contrats.
///      Pour lire le récit : forge test --match-contract ScenariosTest -vv
contract ScenariosTest is Fixture {
    /// @dev Scénario 1 : emprunt adossé à un cryptoactif, baisse du prix, puis liquidation.
    function test_Scenario1_PriceDropThenLiquidation() public {
        console.log(unicode"=== Scénario 1 : emprunt contre des tETH, baisse du prix, liquidation ===");

        // 1. Le prêteur dépose 100 000 tUSDC dans le pool.
        _deposit(lender, 100_000 * USDC);
        console.log(unicode"1. Le prêteur dépose 100 000 tUSDC dans le pool.");
        console.log(string.concat(unicode"   Liquidité du pool : ", _usdc(pool.totalLiquidity())));

        // 2. L'emprunteur dépose 10 tETH (20 000 $) et emprunte 15 000 tUSDC, la limite de 75 %.
        _depositCollateral(borrower, 10 * ETH);
        _borrow(borrower, 15_000 * USDC);
        assertGt(pool.healthFactor(borrower), 1e18);
        assertEq(pool.getBorrowers().length, 1);
        LendingPool.AccountPosition memory p = pool.getAccountPosition(borrower);
        console.log(unicode"2. L'emprunteur dépose 10 tETH en garantie, puis emprunte 15 000 tUSDC.");
        console.log(string.concat(unicode"   Valeur de sa garantie : ", _usd(p.collateralValue)));
        console.log(string.concat(unicode"   Sa dette : ", _usdc(p.debt), unicode", soit la limite de 75 %"));
        console.log(
            string.concat(unicode"   Facteur de santé : ", _ratio(p.healthFactor), unicode" (au-dessus de 1 : saine)")
        );

        // 3. L'équipe baisse le prix de tETH dans l'oracle : 2 000 $ -> 1 800 $.
        //    Le facteur de santé passe sous 1 et la position devient liquidable.
        _setEthPrice(1_800e18);
        p = pool.getAccountPosition(borrower);
        assertEq(p.healthFactor, 0.96e18);
        assertTrue(p.liquidatable);
        console.log(unicode"3. L'administrateur baisse le prix du tETH dans l'oracle : 2 000 $ -> 1 800 $.");
        console.log(string.concat(unicode"   Valeur de la garantie : ", _usd(p.collateralValue)));
        console.log(
            string.concat(unicode"   Facteur de santé : ", _ratio(p.healthFactor), unicode" (sous 1 : liquidable)")
        );

        // 4. Le liquidateur rembourse 50 % de la dette et reçoit la garantie avec 5 % de bonus.
        (, uint256 bonusValue) = pool.previewLiquidation(p.maxLiquidationRepay);
        vm.prank(liquidator);
        uint256 seized = pool.liquidate(borrower, p.maxLiquidationRepay);
        assertEq(seized, 4.375e18);
        assertFalse(pool.getAccountPosition(borrower).liquidatable);
        console.log(
            string.concat(
                unicode"4. Le liquidateur rembourse ", _usdc(p.maxLiquidationRepay), unicode", la moitié de la dette."
            )
        );
        console.log(string.concat(unicode"   Il reçoit ", _teth(seized), unicode" de la garantie."));
        console.log(string.concat(unicode"   Son gain : ", _usd(bonusValue), unicode", le bonus de 5 %"));
        p = pool.getAccountPosition(borrower);
        console.log(string.concat(unicode"   Dette restante de l'emprunteur : ", _usdc(p.debt)));
        console.log(
            string.concat(unicode"   Facteur de santé : ", _ratio(p.healthFactor), unicode" (de nouveau saine)")
        );

        // 5. L'emprunteur rembourse le reste et reprend la garantie qui lui reste.
        vm.startPrank(borrower);
        pool.repay(type(uint256).max);
        pool.withdrawCollateral(5.625e18);
        vm.stopPrank();
        assertEq(pool.getBorrowers().length, 0);
        assertEq(eth.balanceOf(address(pool)), 0);
        console.log(string.concat(unicode"5. L'emprunteur rembourse le reste et reprend ses ", _teth(5.625e18), "."));

        // 6. Le prêteur retire tout : ses fonds sont intacts.
        vm.prank(lender);
        uint256 withdrawn = pool.withdraw(type(uint256).max);
        assertEq(withdrawn, 100_000 * USDC);
        console.log(
            string.concat(unicode"6. Le prêteur retire tout : ", _usdc(withdrawn), unicode". Ses fonds sont intacts.")
        );
    }

    /// @dev Scénario 2 : emprunt adossé à un actif réel, nouvelle expertise, puis rachat.
    function test_Scenario2_NewAppraisalThenBuyout() public {
        console.log(unicode"=== Scénario 2 : emprunt contre une maison tokenisée, nouvelle expertise, rachat ===");

        _deposit(lender, 100_000 * USDC);
        console.log(unicode"1. Le prêteur dépose 100 000 tUSDC dans le pool.");

        // 1. L'émetteur expertise une maison à 100 000 $ et émet le jeton pour l'emprunteur.
        uint256 tokenId = _mintRwa(borrower, 100_000e18);
        assertEq(rwa.getAsset(tokenId).assetType, "Maison");
        console.log(unicode"2. L'émetteur expertise une maison et crée son jeton pour l'emprunteur.");
        console.log(string.concat(unicode"   Valeur expertisée : ", _usd(rwa.getAsset(tokenId).appraisedValue)));

        // 2. L'emprunteur dépose le jeton et emprunte 50 000 tUSDC, la limite de 50 %.
        vm.startPrank(borrower);
        pool.depositRwa(tokenId);
        pool.borrowAgainstRwa(tokenId, 50_000 * USDC);
        vm.stopPrank();
        assertEq(pool.rwaHealthFactor(tokenId), 1.2e18);
        LendingPool.RwaPositionInfo memory p = pool.getRwaPosition(tokenId);
        console.log(unicode"3. L'emprunteur dépose le jeton en garantie et emprunte 50 000 tUSDC.");
        console.log(string.concat(unicode"   Sa dette : ", _usdc(p.debt), unicode", soit la limite de 50 %"));
        console.log(
            string.concat(unicode"   Facteur de santé : ", _ratio(p.healthFactor), unicode" (au-dessus de 1 : saine)")
        );

        // 3. L'émetteur inscrit une expertise plus basse : 80 000 $.
        //    La dette dépasse 60 % de la valeur : la position devient disponible au rachat.
        vm.prank(admin);
        rwa.updateAppraisal(tokenId, 80_000e18, keccak256("expertise-2"));
        p = pool.getRwaPosition(tokenId);
        assertTrue(p.liquidatable);
        assertEq(p.buyoutPrice, 76_000 * USDC);
        console.log(unicode"4. L'émetteur inscrit une nouvelle expertise, plus basse.");
        console.log(string.concat(unicode"   Valeur expertisée : ", _usd(p.appraisedValue)));
        console.log(
            string.concat(
                unicode"   Facteur de santé : ", _ratio(p.healthFactor), unicode" (sous 1 : rachat possible)"
            )
        );
        console.log(
            string.concat(unicode"   Prix du rachat : ", _usdc(p.buyoutPrice), unicode", l'expertise moins 5 %")
        );

        // 4. Le liquidateur rachète le jeton à la valeur expertisée moins 5 %.
        uint256 borrowerBefore = usdc.balanceOf(borrower);
        vm.prank(liquidator);
        uint256 price = pool.buyoutRwa(tokenId);

        // Le pool est remboursé, l'emprunteur reçoit le solde et le liquidateur reçoit le jeton.
        assertEq(pool.totalBorrows(), 0);
        assertEq(pool.totalCash(), 100_000 * USDC);
        assertEq(usdc.balanceOf(borrower), 76_000 * USDC);
        assertEq(rwa.ownerOf(tokenId), liquidator);
        console.log(string.concat(unicode"5. Le liquidateur rachète le jeton pour ", _usdc(price), "."));
        console.log(string.concat(unicode"   Le pool récupère la dette : ", _usdc(p.debt)));
        console.log(
            string.concat(
                unicode"   L'emprunteur reçoit le solde : ", _usdc(usdc.balanceOf(borrower) - borrowerBefore)
            )
        );
        console.log(unicode"   Le liquidateur devient propriétaire du jeton de la maison.");
    }

    // ----- Écriture du récit -----

    function _usdc(uint256 amount) internal pure returns (string memory) {
        return string.concat(_dec(amount, USDC, 2), " tUSDC");
    }

    function _teth(uint256 amount) internal pure returns (string memory) {
        return string.concat(_dec(amount, ETH, 3), " tETH");
    }

    function _usd(uint256 value) internal pure returns (string memory) {
        return string.concat(_dec(value, WAD, 2), " $");
    }

    function _ratio(uint256 value) internal pure returns (string memory) {
        return _dec(value, WAD, 2);
    }

    /// @dev Écrit `value / unit` avec `digits` chiffres après la virgule : 4,375 ou 100 000,00.
    function _dec(uint256 value, uint256 unit, uint256 digits) internal pure returns (string memory) {
        string memory frac = vm.toString((value % unit) * 10 ** digits / unit);
        while (bytes(frac).length < digits) frac = string.concat("0", frac);
        return string.concat(_int(value / unit), ",", frac);
    }

    /// @dev Écrit un entier avec une espace entre les milliers : 100 000.
    function _int(uint256 n) internal pure returns (string memory s) {
        s = vm.toString(n % 1000);
        while (n >= 1000) {
            // complète à trois chiffres le groupe qui vient d'être écrit
            if (n % 1000 < 100) s = string.concat(n % 1000 < 10 ? "00" : "0", s);
            n /= 1000;
            s = string.concat(vm.toString(n % 1000), " ", s);
        }
    }
}
