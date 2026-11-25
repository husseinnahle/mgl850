// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {TestToken} from "../src/TestToken.sol";
import {RWANFT} from "../src/RWANFT.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @notice Test de bout en bout : rejoue les deux scénarios de la démonstration avec de vraies
///         transactions, sur les contrats déjà déployés. Mêmes montants que la section
///         « Scénarios de démonstration » du README.
/// @dev Un seul compte joue tous les rôles : prêteur, emprunteur, liquidateur et émetteur RWA.
///      C'est le compte qui a déployé, le seul autorisé à changer les prix et les expertises.
///      Chaque étape vérifie l'état attendu pendant la simulation. À la fin, le prix du tETH est
///      revenu à 2 000 $ et le compte a retiré tous ses fonds ; le jeton RWA du test lui reste.
///
///      Le script refuse de démarrer si quelqu'un d'autre a une position d'emprunt : baisser le
///      prix du tETH la rendrait liquidable le temps du test.
///
///      Simulation seule, gratuite et sans mot de passe :
///        forge script script/EndToEnd.s.sol --rpc-url sepolia --sender <adresse du compte>
///      Pour de vrai, une vingtaine de transactions, environ 4 minutes sur Sepolia :
///        forge script script/EndToEnd.s.sol --rpc-url sepolia --broadcast --account deployer
///          --sender <adresse du compte> --slow --gas-estimate-multiplier 200
///
///      `--gas-estimate-multiplier 200` : sur la chaîne, le temps passe entre deux transactions et
///      le pool calcule les intérêts courus, ce qui consomme plus de gaz que dans la simulation.
contract EndToEnd is Script {
    uint256 private constant USDC = 1e6;
    uint256 private constant ETH = 1e18;
    uint256 private constant WAD = 1e18;

    TestToken private tUSDC;
    TestToken private tETH;
    RWANFT private rwaNft;
    PriceOracle private oracle;
    LendingPool private pool;
    address private me;

    function run() external {
        string memory json = vm.readFile(string.concat("deployments/", vm.toString(block.chainid), ".json"));
        tUSDC = TestToken(vm.parseJsonAddress(json, ".tUSDC"));
        tETH = TestToken(vm.parseJsonAddress(json, ".tETH"));
        rwaNft = RWANFT(vm.parseJsonAddress(json, ".RWANFT"));
        oracle = PriceOracle(vm.parseJsonAddress(json, ".PriceOracle"));
        pool = LendingPool(vm.parseJsonAddress(json, ".LendingPool"));
        me = msg.sender;

        require(me == vm.parseJsonAddress(json, ".deployer"), "Lancer avec le compte qui a deploye les contrats");
        require(pool.getBorrowers().length == 0, "Quelqu'un a une dette contre tETH : test annule");
        require(pool.getRwaTokenIds().length == 0, "Un jeton RWA est deja en garantie : test annule");
        require(pool.sharesOf(me) == 0, "Le compte a deja un depot dans le pool : test annule");

        vm.startBroadcast();
        _prepare();
        _fungibleScenario();
        _rwaScenario();
        _withdrawEverything();
        vm.stopBroadcast();
    }

    function _prepare() private {
        tUSDC.faucet(); // 10 000 tUSDC
        tETH.faucet(); // 10 tETH
        tUSDC.mint(me, 200_000 * USDC); // le compte est propriétaire du jeton de test
        tUSDC.approve(address(pool), type(uint256).max);
        tETH.approve(address(pool), type(uint256).max);
        rwaNft.setApprovalForAll(address(pool), true);
        console2.log(unicode"0. Jetons de test reçus avec faucet() et mint(), approbations données au pool.");
    }

    /// @dev Scénario 1 : emprunt contre des tETH, baisse du prix, puis liquidation.
    function _fungibleScenario() private {
        console2.log(unicode"=== Scénario 1 : emprunt contre des tETH, baisse du prix, liquidation ===");

        pool.deposit(100_000 * USDC);
        pool.depositCollateral(10 * ETH);
        pool.borrow(12_000 * USDC);
        LendingPool.AccountPosition memory p = pool.getAccountPosition(me);
        require(p.debt == 12_000 * USDC && !p.liquidatable, "Emprunt : position inattendue");
        console2.log(unicode"1. Dépôt de 100 000 tUSDC, garantie de 10 tETH, emprunt de 12 000 tUSDC.");
        console2.log(string.concat(unicode"   Facteur de santé : ", _ratio(p.healthFactor)));

        oracle.setPrice(address(tETH), 1_400e18);
        p = pool.getAccountPosition(me);
        require(p.liquidatable, "Baisse du prix : la position devrait etre liquidable");
        console2.log(unicode"2. Prix du tETH baissé à 1 400 $.");
        console2.log(
            string.concat(unicode"   Facteur de santé : ", _ratio(p.healthFactor), unicode" (sous 1 : liquidable)")
        );

        uint256 seized = pool.liquidate(me, 6_000 * USDC);
        require(seized == 4.5e18, "Liquidation : garantie saisie inattendue");
        console2.log(
            string.concat(
                unicode"3. Liquidation de 6 000 tUSDC : ", _teth(seized), unicode" reçus, bonus de 5 % compris."
            )
        );

        pool.repay(type(uint256).max);
        pool.withdrawCollateral(pool.collateralOf(me));
        require(pool.getBorrowers().length == 0 && pool.collateralOf(me) == 0, "Remboursement : position non soldee");
        oracle.setPrice(address(tETH), 2_000e18);
        console2.log(unicode"4. Reste de la dette remboursé, garantie reprise, prix du tETH remis à 2 000 $.");
    }

    /// @dev Scénario 2 : emprunt contre une maison tokenisée, nouvelle expertise, puis rachat.
    function _rwaScenario() private {
        console2.log(unicode"=== Scénario 2 : emprunt contre une maison tokenisée, nouvelle expertise, rachat ===");

        uint256 tokenId = rwaNft.mint(me, "Maison", 100_000e18, keccak256("test-bout-en-bout-expertise-1"));
        pool.depositRwa(tokenId);
        pool.borrowAgainstRwa(tokenId, 40_000 * USDC);
        LendingPool.RwaPositionInfo memory r = pool.getRwaPosition(tokenId);
        require(r.debt == 40_000 * USDC && !r.liquidatable, "Emprunt RWA : position inattendue");
        console2.log(
            string.concat(
                unicode"5. Maison expertisée 100 000 $ (jeton n° ",
                vm.toString(tokenId),
                unicode"), déposée en garantie, emprunt de 40 000 tUSDC."
            )
        );
        console2.log(string.concat(unicode"   Facteur de santé : ", _ratio(r.healthFactor)));

        rwaNft.updateAppraisal(tokenId, 60_000e18, keccak256("test-bout-en-bout-expertise-2"));
        r = pool.getRwaPosition(tokenId);
        require(r.liquidatable && r.buyoutPrice == 57_000 * USDC, "Nouvelle expertise : rachat impossible");
        console2.log(unicode"6. Nouvelle expertise de la maison : 60 000 $.");
        console2.log(
            string.concat(
                unicode"   Facteur de santé : ", _ratio(r.healthFactor), unicode" (sous 1 : rachat possible)"
            )
        );

        uint256 price = pool.buyoutRwa(tokenId);
        require(rwaNft.ownerOf(tokenId) == me && pool.getRwaTokenIds().length == 0, "Rachat : jeton non transfere");
        console2.log(
            string.concat(unicode"7. Rachat du jeton pour ", _usdc(price), unicode", la valeur expertisée moins 5 %.")
        );
        console2.log(
            unicode"   Le pool récupère sa dette, l'emprunteur reçoit le solde, le liquidateur reçoit le jeton."
        );
    }

    function _withdrawEverything() private {
        uint256 withdrawn = pool.withdraw(type(uint256).max);
        require(pool.sharesOf(me) == 0, "Retrait : il reste un depot");
        console2.log(string.concat(unicode"8. Le prêteur retire tout son dépôt : ", _usdc(withdrawn), "."));
    }

    // ----- Écriture des montants -----

    function _usdc(uint256 amount) private pure returns (string memory) {
        return string.concat(_dec(amount, USDC, 2), " tUSDC");
    }

    function _teth(uint256 amount) private pure returns (string memory) {
        return string.concat(_dec(amount, ETH, 3), " tETH");
    }

    function _ratio(uint256 value) private pure returns (string memory) {
        return _dec(value, WAD, 2);
    }

    /// @dev Écrit `value / unit` avec `digits` chiffres après la virgule : 4,500 ou 100 000,00.
    function _dec(uint256 value, uint256 unit, uint256 digits) private pure returns (string memory) {
        string memory frac = vm.toString((value % unit) * 10 ** digits / unit);
        while (bytes(frac).length < digits) frac = string.concat("0", frac);
        return string.concat(_int(value / unit), ",", frac);
    }

    /// @dev Écrit un entier avec une espace entre les milliers : 100 000.
    function _int(uint256 n) private pure returns (string memory s) {
        s = vm.toString(n % 1000);
        while (n >= 1000) {
            // complète à trois chiffres le groupe qui vient d'être écrit
            if (n % 1000 < 100) s = string.concat(n % 1000 < 10 ? "00" : "0", s);
            n /= 1000;
            s = string.concat(vm.toString(n % 1000), " ", s);
        }
    }
}
