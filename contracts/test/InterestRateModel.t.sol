// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {InterestRateModel} from "../src/InterestRateModel.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice EF-22 à EF-24 et EF-26.
/// @dev Modèle des tests : base 2 %, +8 % jusqu'à U = 80 %, +100 % au-delà, réserve 10 %.
contract InterestRateModelTest is Fixture {
    function test_Utilization() public view {
        // Rien d'emprunté : 0 %.
        assertEq(model.utilization(100_000e6, 0, 0), 0);
        // 15 000 empruntés sur 100 000 de fonds : 15 %.
        assertEq(model.utilization(85_000e6, 15_000e6, 0), 0.15e18);
        // Tout est emprunté : 100 %.
        assertEq(model.utilization(0, 100e6, 0), 1e18);
        // La réserve n'appartient pas aux prêteurs : 50 / (60 + 50 - 10) = 50 %.
        assertEq(model.utilization(60e6, 50e6, 10e6), 0.5e18);
        // Le résultat ne dépasse jamais 100 %.
        assertEq(model.utilization(0, 100e6, 50e6), 1e18);
        assertEq(model.utilization(0, 100e6, 200e6), 1e18);
    }

    function test_BorrowRate_FollowsTwoSlopes() public view {
        assertEq(model.borrowRate(0), 0.02e18); // taux de base
        assertEq(model.borrowRate(0.4e18), 0.06e18); // à mi-chemin de la première pente
        assertEq(model.borrowRate(0.8e18), 0.1e18); // au point d'inflexion
        assertEq(model.borrowRate(0.9e18), 0.6e18); // la seconde pente est bien plus forte
        assertEq(model.borrowRate(1e18), 1.1e18); // à 100 % d'utilisation
        assertEq(model.borrowRate(2e18), 1.1e18); // une valeur au-delà de 100 % est plafonnée
    }

    function test_SupplyRate_IsBorrowRateTimesUtilizationLessReserve() public view {
        assertEq(model.supplyRate(0), 0);
        // 6 % x 40 % x (1 - 10 %) = 2,16 %
        assertEq(model.supplyRate(0.4e18), 0.0216e18);
        // 10 % x 80 % x (1 - 10 %) = 7,2 %
        assertEq(model.supplyRate(0.8e18), 0.072e18);
        // 110 % x 100 % x (1 - 10 %) = 99 %, et une valeur au-delà de 100 % est plafonnée
        assertEq(model.supplyRate(1e18), 0.99e18);
        assertEq(model.supplyRate(2e18), 0.99e18);
    }

    function test_SetParameters_ByOwner() public {
        vm.expectEmit(false, false, false, true, address(model));
        emit InterestRateModel.ParametersUpdated(0.01e18, 0.04e18, 0.75e18, 0.9e18, 0.2e18);
        vm.prank(admin);
        model.setParameters(0.01e18, 0.04e18, 0.75e18, 0.9e18, 0.2e18);

        assertEq(model.baseRate(), 0.01e18);
        assertEq(model.slope1(), 0.04e18);
        assertEq(model.slope2(), 0.75e18);
        assertEq(model.kink(), 0.9e18);
        assertEq(model.reserveFactor(), 0.2e18);
        assertEq(model.borrowRate(0.9e18), 0.05e18);
    }

    function test_SetParameters_RevertWhen_CallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        model.setParameters(0.01e18, 0.04e18, 0.75e18, 0.9e18, 0.2e18);
    }

    function test_SetParameters_RevertWhen_KinkIsInvalid() public {
        vm.startPrank(admin);
        vm.expectRevert(InterestRateModel.InvalidKink.selector);
        model.setParameters(0.02e18, 0.08e18, 1e18, 0, 0.1e18);
        vm.expectRevert(InterestRateModel.InvalidKink.selector);
        model.setParameters(0.02e18, 0.08e18, 1e18, 1e18, 0.1e18);
        vm.stopPrank();
    }

    function test_SetParameters_RevertWhen_ReserveFactorAbove100Percent() public {
        vm.prank(admin);
        vm.expectRevert(InterestRateModel.InvalidReserveFactor.selector);
        model.setParameters(0.02e18, 0.08e18, 1e18, 0.8e18, 1e18 + 1);
    }

    function test_SetParameters_RevertWhen_RateIsTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(InterestRateModel.RateTooHigh.selector);
        model.setParameters(1e18, 4e18, 5e18 + 1, 0.8e18, 0.1e18);
    }

    function testFuzz_BorrowRate_NeverDecreasesWithUtilization(uint256 u1, uint256 u2) public view {
        u1 = bound(u1, 0, 1e18);
        u2 = bound(u2, u1, 1e18);

        assertLe(model.borrowRate(u1), model.borrowRate(u2));
    }

    function testFuzz_SupplyRate_NeverExceedsBorrowRate(uint256 u) public view {
        u = bound(u, 0, 1e18);

        assertLe(model.supplyRate(u), model.borrowRate(u));
    }
}
