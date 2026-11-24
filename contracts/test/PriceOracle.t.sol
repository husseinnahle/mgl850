// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PriceOracle} from "../src/PriceOracle.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice EF-27 à EF-29 (prix des jetons) et EF-40 (valeur expertisée des jetons RWA).
contract PriceOracleTest is Fixture {
    function test_Constructor_RevertWhen_RwaContractIsZeroAddress() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        new PriceOracle(admin, address(0), 30 days, 365 days);
    }

    // ----- Prix des jetons ERC-20 -----

    function test_SetPrice_StoresPriceAndTimestamp() public {
        vm.warp(START + 1 hours);

        vm.expectEmit(true, false, false, true, address(oracle));
        emit PriceOracle.PriceUpdated(address(eth), ETH_PRICE, 1_800e18, START + 1 hours);
        _setEthPrice(1_800e18);

        assertEq(oracle.getPrice(address(eth)), 1_800e18);
        (uint256 price, uint256 updatedAt, bool valid) = oracle.priceData(address(eth));
        assertEq(price, 1_800e18);
        assertEq(updatedAt, START + 1 hours);
        assertTrue(valid);
    }

    function test_SetPrice_RevertWhen_PriceIsZero() public {
        vm.prank(admin);
        vm.expectRevert(PriceOracle.ZeroPrice.selector);
        oracle.setPrice(address(eth), 0);
    }

    function test_SetPrice_RevertWhen_TokenIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.setPrice(address(0), 1e18);
    }

    function test_SetPrice_RevertWhen_CallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.setPrice(address(eth), 1e18);
    }

    function test_GetPrice_RevertWhen_PriceWasNeverSet() public {
        address unknownToken = makeAddr("unknownToken");

        vm.expectRevert(abi.encodeWithSelector(PriceOracle.PriceNotSet.selector, unknownToken));
        oracle.getPrice(unknownToken);

        (uint256 price,, bool valid) = oracle.priceData(unknownToken);
        assertEq(price, 0);
        assertFalse(valid);
    }

    function test_GetPrice_RevertWhen_PriceIsStale() public {
        // À la limite de validité (30 jours), le prix est encore accepté.
        vm.warp(START + 30 days);
        assertEq(oracle.getPrice(address(eth)), ETH_PRICE);

        // Une seconde plus tard, il est périmé : rejeté par getPrice, signalé par priceData.
        vm.warp(START + 30 days + 1);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.StalePrice.selector, address(eth), START));
        oracle.getPrice(address(eth));

        (uint256 price, uint256 updatedAt, bool valid) = oracle.priceData(address(eth));
        assertEq(price, ETH_PRICE);
        assertEq(updatedAt, START);
        assertFalse(valid);

        // Une nouvelle inscription le rend de nouveau valide.
        _setEthPrice(ETH_PRICE);
        assertEq(oracle.getPrice(address(eth)), ETH_PRICE);
    }

    // ----- Valeur expertisée des jetons RWA -----

    function test_GetRwaValue_ReadsAppraisalFromToken() public {
        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        (uint256 value, uint256 appraisedAt) = oracle.getRwaValue(tokenId);
        assertEq(value, 100_000e18);
        assertEq(appraisedAt, START);

        (uint256 dataValue, uint256 dataDate, bool valid) = oracle.rwaValueData(tokenId);
        assertEq(dataValue, 100_000e18);
        assertEq(dataDate, START);
        assertTrue(valid);
    }

    function test_GetRwaValue_RevertWhen_TokenHasNoAppraisal() public {
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.AppraisalNotSet.selector, 42));
        oracle.getRwaValue(42);

        (uint256 value,, bool valid) = oracle.rwaValueData(42);
        assertEq(value, 0);
        assertFalse(valid);
    }

    function test_GetRwaValue_RevertWhen_AppraisalIsStale() public {
        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        vm.warp(START + 365 days + 1);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.StaleAppraisal.selector, tokenId, START));
        oracle.getRwaValue(tokenId);

        (,, bool valid) = oracle.rwaValueData(tokenId);
        assertFalse(valid);

        // Une nouvelle expertise rend la valeur de nouveau utilisable.
        vm.prank(admin);
        rwa.updateAppraisal(tokenId, 90_000e18, keccak256("expertise-2"));

        (uint256 value, uint256 appraisedAt) = oracle.getRwaValue(tokenId);
        assertEq(value, 90_000e18);
        assertEq(appraisedAt, START + 365 days + 1);
    }

    // ----- Durées de validité -----

    function test_SetMaxAges_ByOwner() public {
        vm.expectEmit(false, false, false, true, address(oracle));
        emit PriceOracle.MaxAgesUpdated(1 days, 90 days);
        vm.prank(admin);
        oracle.setMaxAges(1 days, 90 days);

        assertEq(oracle.maxPriceAge(), 1 days);
        assertEq(oracle.maxAppraisalAge(), 90 days);
    }

    function test_SetMaxAges_RevertWhen_DurationIsZero() public {
        vm.startPrank(admin);
        vm.expectRevert(PriceOracle.ZeroDuration.selector);
        oracle.setMaxAges(0, 90 days);
        vm.expectRevert(PriceOracle.ZeroDuration.selector);
        oracle.setMaxAges(1 days, 0);
        vm.stopPrank();
    }

    function test_SetMaxAges_RevertWhen_CallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.setMaxAges(1 days, 90 days);
    }
}
