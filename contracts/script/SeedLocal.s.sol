// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {TestToken} from "../src/TestToken.sol";
import {RWANFT} from "../src/RWANFT.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @notice Remplit une chaîne locale Anvil avec un état de départ, pour développer l'interface
///         sans tout saisir à la main : un prêteur, un emprunteur avec ses deux types de
///         position, et un liquidateur qui a des fonds.
/// @dev À lancer après Deploy.s.sol, sur Anvil seulement. Les comptes sont ceux qu'Anvil crée
///      à chaque démarrage à partir de sa phrase de test publique. Ces comptes sont connus de
///      tous : ne jamais les utiliser sur un vrai réseau.
///        compte 0 : administrateur et émetteur RWA (celui qui a déployé)
///        compte 1 : prêteur
///        compte 2 : emprunteur
///        compte 3 : liquidateur
///
///      À lancer avec `--gas-estimate-multiplier 200`. `forge script` estime le gaz en simulant
///      toutes les transactions au même instant. Sur la chaîne, chaque transaction arrive après
///      la précédente : le pool calcule alors les intérêts courus, ce qui consomme plus de gaz
///      que dans la simulation. Sans cette marge, le dernier emprunt échoue par manque de gaz.
contract SeedLocal is Script {
    string internal constant ANVIL_MNEMONIC = "test test test test test test test test test test test junk";

    function run() external {
        require(block.chainid == 31337, "SeedLocal : chaine locale Anvil seulement");

        string memory json = vm.readFile("deployments/31337.json");
        TestToken tUSDC = TestToken(vm.parseJsonAddress(json, ".tUSDC"));
        TestToken tETH = TestToken(vm.parseJsonAddress(json, ".tETH"));
        RWANFT rwaNft = RWANFT(vm.parseJsonAddress(json, ".RWANFT"));
        LendingPool pool = LendingPool(vm.parseJsonAddress(json, ".LendingPool"));

        uint256 adminKey = vm.deriveKey(ANVIL_MNEMONIC, 0);
        uint256 lenderKey = vm.deriveKey(ANVIL_MNEMONIC, 1);
        uint256 borrowerKey = vm.deriveKey(ANVIL_MNEMONIC, 2);
        address lender = vm.addr(lenderKey);
        address borrower = vm.addr(borrowerKey);
        address liquidator = vm.addr(vm.deriveKey(ANVIL_MNEMONIC, 3));

        // L'administrateur distribue des jetons de test et tokenise une maison pour l'emprunteur.
        vm.startBroadcast(adminKey);
        tUSDC.mint(lender, 200_000e6);
        tUSDC.mint(liquidator, 200_000e6);
        tETH.mint(borrower, 20e18);
        uint256 tokenId = rwaNft.mint(borrower, "Maison", 100_000e18, keccak256("expertise-maison-001"));
        vm.stopBroadcast();

        // Le prêteur dépose 100 000 tUSDC.
        vm.startBroadcast(lenderKey);
        tUSDC.approve(address(pool), type(uint256).max);
        pool.deposit(100_000e6);
        vm.stopBroadcast();

        // L'emprunteur ouvre ses deux positions :
        // 10 tETH (20 000 $) contre 12 000 tUSDC, et la maison (100 000 $) contre 40 000 tUSDC.
        vm.startBroadcast(borrowerKey);
        tETH.approve(address(pool), type(uint256).max);
        pool.depositCollateral(10e18);
        pool.borrow(12_000e6);
        rwaNft.approve(address(pool), tokenId);
        pool.depositRwa(tokenId);
        pool.borrowAgainstRwa(tokenId, 40_000e6);
        vm.stopBroadcast();

        console2.log("Preteur     ", lender);
        console2.log("Emprunteur  ", borrower);
        console2.log("Liquidateur ", liquidator);
        console2.log("Jeton RWA depose en garantie :", tokenId);
    }
}
