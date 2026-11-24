// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {TestToken} from "../../src/TestToken.sol";
import {RWANFT} from "../../src/RWANFT.sol";
import {PriceOracle} from "../../src/PriceOracle.sol";
import {InterestRateModel} from "../../src/InterestRateModel.sol";
import {LendingPool} from "../../src/LendingPool.sol";

/// @notice Base commune des tests : déploie tout le protocole et prépare quatre acteurs.
/// @dev Paramètres du modèle de taux : base 2 %, +8 % jusqu'au point d'inflexion (80 %),
///      +100 % au-delà, facteur de réserve 10 %. Prix : tETH = 2 000 $, tUSDC = 1 $.
abstract contract Fixture is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant USDC = 1e6; // un tUSDC entier (6 décimales)
    uint256 internal constant ETH = 1e18; // un tETH entier (18 décimales)
    uint256 internal constant ETH_PRICE = 2_000e18;
    uint256 internal constant USDC_PRICE = 1e18;
    uint256 internal constant START = 1_800_000_000; // horodatage de départ des tests

    address internal admin = makeAddr("admin"); // propriétaire des contrats et émetteur RWA
    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");
    address internal liquidator = makeAddr("liquidator");
    address internal stranger = makeAddr("stranger"); // n'a aucun jeton

    TestToken internal usdc;
    TestToken internal eth;
    RWANFT internal rwa;
    PriceOracle internal oracle;
    InterestRateModel internal model;
    LendingPool internal pool;

    function setUp() public virtual {
        vm.warp(START);

        vm.startPrank(admin);
        usdc = new TestToken("Test USD Coin", "tUSDC", 6, 10_000 * USDC, admin);
        eth = new TestToken("Test Ether", "tETH", 18, 10 * ETH, admin);
        rwa = new RWANFT(admin, admin);
        oracle = new PriceOracle(admin, address(rwa), 30 days, 365 days);
        model = new InterestRateModel(admin, 0.02e18, 0.08e18, 1e18, 0.8e18, 0.1e18);
        pool = new LendingPool(address(usdc), address(eth), address(rwa), address(oracle), address(model));

        oracle.setPrice(address(eth), ETH_PRICE);
        oracle.setPrice(address(usdc), USDC_PRICE);

        usdc.mint(lender, 1_000_000 * USDC);
        usdc.mint(liquidator, 1_000_000 * USDC);
        eth.mint(borrower, 100 * ETH);
        vm.stopPrank();

        address[4] memory users = [lender, borrower, liquidator, stranger];
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);
            usdc.approve(address(pool), type(uint256).max);
            eth.approve(address(pool), type(uint256).max);
            rwa.setApprovalForAll(address(pool), true);
            vm.stopPrank();
        }
    }

    // ----- Raccourcis -----

    function _deposit(address user, uint256 amount) internal {
        vm.prank(user);
        pool.deposit(amount);
    }

    function _depositCollateral(address user, uint256 amount) internal {
        vm.prank(user);
        pool.depositCollateral(amount);
    }

    function _borrow(address user, uint256 amount) internal {
        vm.prank(user);
        pool.borrow(amount);
    }

    function _setEthPrice(uint256 price) internal {
        vm.prank(admin);
        oracle.setPrice(address(eth), price);
    }

    /// @dev Réinscrit les mêmes prix, pour qu'ils restent valides après un saut dans le temps.
    function _refreshPrices() internal {
        vm.startPrank(admin);
        oracle.setPrice(address(eth), ETH_PRICE);
        oracle.setPrice(address(usdc), USDC_PRICE);
        vm.stopPrank();
    }

    function _mintRwa(address to, uint256 value) internal returns (uint256 tokenId) {
        vm.prank(admin);
        tokenId = rwa.mint(to, "Maison", value, keccak256("expertise-1"));
    }

    /// @dev Situation de référence : le prêteur dépose 100 000 tUSDC, l'emprunteur dépose
    ///      10 tETH (20 000 $) et emprunte 15 000 tUSDC, soit exactement la limite de 75 %.
    function _openFungiblePosition() internal {
        _deposit(lender, 100_000 * USDC);
        _depositCollateral(borrower, 10 * ETH);
        _borrow(borrower, 15_000 * USDC);
    }
}
