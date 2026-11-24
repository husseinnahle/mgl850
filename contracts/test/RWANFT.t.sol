// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {RWANFT} from "../src/RWANFT.sol";
import {Fixture} from "./utils/Fixture.sol";

/// @notice EF-37 (contenu du jeton) et EF-38 (droits de l'émetteur).
contract RWANFTTest is Fixture {
    bytes32 internal constant DOC_1 = keccak256("rapport-expertise-001.pdf");
    bytes32 internal constant DOC_2 = keccak256("rapport-expertise-002.pdf");

    function test_Mint_CreatesTokenWithItsAppraisal() public {
        vm.expectEmit(true, true, false, true, address(rwa));
        emit RWANFT.AssetTokenized(1, borrower, "Maison", 100_000e18, DOC_1);
        vm.prank(admin);
        uint256 tokenId = rwa.mint(borrower, "Maison", 100_000e18, DOC_1);

        assertEq(tokenId, 1);
        assertEq(rwa.ownerOf(tokenId), borrower);
        assertEq(rwa.nextTokenId(), 2);

        RWANFT.Asset memory a = rwa.getAsset(tokenId);
        assertEq(a.assetType, "Maison");
        assertEq(a.appraisedValue, 100_000e18);
        assertEq(a.appraisedAt, START);
        assertEq(a.documentHash, DOC_1);
    }

    function test_Mint_RevertWhen_CallerIsNotIssuer() public {
        vm.prank(stranger);
        vm.expectRevert(RWANFT.NotIssuer.selector);
        rwa.mint(stranger, "Maison", 100_000e18, DOC_1);
    }

    function test_Mint_RevertWhen_ValueIsZero() public {
        vm.prank(admin);
        vm.expectRevert(RWANFT.ZeroValue.selector);
        rwa.mint(borrower, "Maison", 0, DOC_1);
    }

    function test_Mint_RevertWhen_AssetTypeIsEmpty() public {
        vm.prank(admin);
        vm.expectRevert(RWANFT.EmptyAssetType.selector);
        rwa.mint(borrower, "", 100_000e18, DOC_1);
    }

    function test_UpdateAppraisal_RecordsNewValueDateAndDocument() public {
        vm.prank(admin);
        uint256 tokenId = rwa.mint(borrower, "Montre", 12_000e18, DOC_1);

        vm.warp(START + 90 days);
        vm.expectEmit(true, false, false, true, address(rwa));
        emit RWANFT.AppraisalUpdated(tokenId, 12_000e18, 9_500e18, DOC_2);
        vm.prank(admin);
        rwa.updateAppraisal(tokenId, 9_500e18, DOC_2);

        RWANFT.Asset memory a = rwa.getAsset(tokenId);
        assertEq(a.assetType, "Montre");
        assertEq(a.appraisedValue, 9_500e18);
        assertEq(a.appraisedAt, START + 90 days);
        assertEq(a.documentHash, DOC_2);
    }

    function test_UpdateAppraisal_RevertWhen_CallerIsNotIssuer() public {
        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        // Même le propriétaire du jeton ne peut pas réviser sa valeur.
        vm.prank(borrower);
        vm.expectRevert(RWANFT.NotIssuer.selector);
        rwa.updateAppraisal(tokenId, 500_000e18, DOC_2);
    }

    function test_UpdateAppraisal_RevertWhen_TokenDoesNotExist() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        rwa.updateAppraisal(99, 1e18, DOC_2);
    }

    function test_UpdateAppraisal_RevertWhen_ValueIsZero() public {
        uint256 tokenId = _mintRwa(borrower, 100_000e18);

        vm.prank(admin);
        vm.expectRevert(RWANFT.ZeroValue.selector);
        rwa.updateAppraisal(tokenId, 0, DOC_2);
    }

    function test_SetIssuer_MovesTheRightToIssue() public {
        address newIssuer = makeAddr("newIssuer");

        vm.expectEmit(true, true, false, false, address(rwa));
        emit RWANFT.IssuerChanged(admin, newIssuer);
        vm.prank(admin);
        rwa.setIssuer(newIssuer);
        assertEq(rwa.issuer(), newIssuer);

        // Le nouvel émetteur peut émettre...
        vm.prank(newIssuer);
        rwa.mint(borrower, "Bijou", 3_000e18, DOC_1);

        // ...et l'ancien ne le peut plus, même s'il reste propriétaire du contrat.
        vm.prank(admin);
        vm.expectRevert(RWANFT.NotIssuer.selector);
        rwa.mint(borrower, "Bijou", 3_000e18, DOC_1);
    }

    function test_SetIssuer_RevertWhen_CallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        rwa.setIssuer(stranger);
    }

    function test_SetIssuer_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(RWANFT.ZeroAddress.selector);
        rwa.setIssuer(address(0));
    }

    function test_UnknownToken_HasNoAppraisal() public {
        (uint256 value, uint256 appraisedAt) = rwa.appraisalOf(99);
        assertEq(value, 0);
        assertEq(appraisedAt, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        rwa.getAsset(99);
    }

    function test_TokensOf_ListsTokensOfHolder() public {
        vm.startPrank(admin);
        rwa.mint(borrower, "Maison", 100_000e18, DOC_1); // jeton 1
        rwa.mint(lender, "Montre", 12_000e18, DOC_1); // jeton 2
        rwa.mint(borrower, "Bijou", 3_000e18, DOC_1); // jeton 3
        vm.stopPrank();

        uint256[] memory ids = rwa.tokensOf(borrower);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 3);

        assertEq(rwa.tokensOf(stranger).length, 0);
    }
}
