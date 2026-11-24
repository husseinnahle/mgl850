// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {TestToken} from "../src/TestToken.sol";
import {RWANFT} from "../src/RWANFT.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @notice Déploie tout le protocole et écrit les adresses dans deployments/<chainId>.json,
///         le fichier que lit l'interface web.
/// @dev Le compte qui déploie devient propriétaire des jetons, de l'oracle et du modèle de taux,
///      ainsi qu'émetteur des jetons RWA. Voir le README pour les commandes.
contract Deploy is Script {
    // Prix de départ inscrits dans l'oracle (USD, 18 décimales).
    uint256 internal constant TETH_PRICE = 2_000e18;
    uint256 internal constant TUSDC_PRICE = 1e18;

    // Durées de validité des valeurs de l'oracle. Elles sont longues parce que les prix sont
    // inscrits à la main : penser à les réinscrire avant une démonstration.
    uint256 internal constant MAX_PRICE_AGE = 30 days;
    uint256 internal constant MAX_APPRAISAL_AGE = 365 days;

    // Modèle de taux : 2 % de base, +8 % jusqu'à 80 % d'utilisation, +100 % au-delà, réserve de 10 %.
    uint256 internal constant BASE_RATE = 0.02e18;
    uint256 internal constant SLOPE_1 = 0.08e18;
    uint256 internal constant SLOPE_2 = 1e18;
    uint256 internal constant KINK = 0.8e18;
    uint256 internal constant RESERVE_FACTOR = 0.1e18;

    function run() external {
        address deployer = msg.sender;

        vm.startBroadcast();

        TestToken tUSDC = new TestToken("Test USD Coin", "tUSDC", 6, 10_000e6, deployer);
        TestToken tETH = new TestToken("Test Ether", "tETH", 18, 10e18, deployer);
        RWANFT rwaNft = new RWANFT(deployer, deployer);
        PriceOracle oracle = new PriceOracle(deployer, address(rwaNft), MAX_PRICE_AGE, MAX_APPRAISAL_AGE);
        InterestRateModel rateModel = new InterestRateModel(deployer, BASE_RATE, SLOPE_1, SLOPE_2, KINK, RESERVE_FACTOR);
        LendingPool pool =
            new LendingPool(address(tUSDC), address(tETH), address(rwaNft), address(oracle), address(rateModel));

        oracle.setPrice(address(tETH), TETH_PRICE);
        oracle.setPrice(address(tUSDC), TUSDC_PRICE);

        vm.stopBroadcast();

        console2.log("Deployeur         ", deployer);
        console2.log("tUSDC             ", address(tUSDC));
        console2.log("tETH              ", address(tETH));
        console2.log("RWANFT            ", address(rwaNft));
        console2.log("PriceOracle       ", address(oracle));
        console2.log("InterestRateModel ", address(rateModel));
        console2.log("LendingPool       ", address(pool));

        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "deployBlock", block.number);
        vm.serializeAddress(key, "deployer", deployer);
        vm.serializeAddress(key, "tUSDC", address(tUSDC));
        vm.serializeAddress(key, "tETH", address(tETH));
        vm.serializeAddress(key, "RWANFT", address(rwaNft));
        vm.serializeAddress(key, "PriceOracle", address(oracle));
        vm.serializeAddress(key, "InterestRateModel", address(rateModel));
        string memory json = vm.serializeAddress(key, "LendingPool", address(pool));

        vm.createDir("deployments", true);
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Adresses ecrites dans", path);
    }
}
