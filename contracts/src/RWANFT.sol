// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title RWANFT
/// @notice Jeton ERC-721 qui représente un actif réel expertisé : une maison, une montre, un bijou (EF-37).
/// @dev Chaque jeton porte le type de bien, sa valeur expertisée, la date de l'expertise et l'empreinte
///      du document justificatif. Seul l'émetteur autorisé peut émettre un jeton ou réviser sa valeur (EF-38).
///      Ce contrat est la seule source de la valeur expertisée : l'oracle la lit ici.
contract RWANFT is ERC721, Ownable {
    struct Asset {
        string assetType; // type de bien, par exemple « Maison »
        uint256 appraisedValue; // valeur expertisée en USD, sur 18 décimales
        uint256 appraisedAt; // horodatage de la dernière expertise
        bytes32 documentHash; // empreinte du document justificatif
    }

    /// @notice Émetteur autorisé : l'acteur de confiance qui expertise les biens.
    address public issuer;

    /// @notice Identifiant du prochain jeton émis. Les identifiants commencent à 1.
    uint256 public nextTokenId = 1;

    mapping(uint256 tokenId => Asset) private _assets;

    event IssuerChanged(address indexed previousIssuer, address indexed newIssuer);
    event AssetTokenized(
        uint256 indexed tokenId, address indexed to, string assetType, uint256 appraisedValue, bytes32 documentHash
    );
    event AppraisalUpdated(uint256 indexed tokenId, uint256 oldValue, uint256 newValue, bytes32 documentHash);

    error NotIssuer();
    error ZeroAddress();
    error ZeroValue();
    error EmptyAssetType();

    modifier onlyIssuer() {
        if (msg.sender != issuer) revert NotIssuer();
        _;
    }

    constructor(address owner_, address issuer_) ERC721(unicode"Actif réel tokenisé", "RWA") Ownable(owner_) {
        _setIssuer(issuer_);
    }

    /// @notice Désigne l'émetteur autorisé. Réservé au propriétaire du contrat.
    function setIssuer(address newIssuer) external onlyOwner {
        _setIssuer(newIssuer);
    }

    /// @notice Tokenise un actif réel expertisé (UC16).
    /// @param to Propriétaire du bien, qui reçoit le jeton.
    /// @param assetType Type de bien.
    /// @param appraisedValue Valeur expertisée en USD, sur 18 décimales.
    /// @param documentHash Empreinte du document justificatif de l'expertise.
    function mint(address to, string calldata assetType, uint256 appraisedValue, bytes32 documentHash)
        external
        onlyIssuer
        returns (uint256 tokenId)
    {
        if (appraisedValue == 0) revert ZeroValue();
        if (bytes(assetType).length == 0) revert EmptyAssetType();

        tokenId = nextTokenId++;
        _assets[tokenId] = Asset({
            assetType: assetType,
            appraisedValue: appraisedValue,
            appraisedAt: block.timestamp,
            documentHash: documentHash
        });

        // L'événement est émis avant `_safeMint`, qui peut appeler le contrat destinataire.
        emit AssetTokenized(tokenId, to, assetType, appraisedValue, documentHash);
        _safeMint(to, tokenId);
    }

    /// @notice Inscrit une nouvelle expertise pour un jeton déjà émis (UC17).
    function updateAppraisal(uint256 tokenId, uint256 newValue, bytes32 documentHash) external onlyIssuer {
        _requireOwned(tokenId);
        if (newValue == 0) revert ZeroValue();

        Asset storage a = _assets[tokenId];
        uint256 oldValue = a.appraisedValue;
        a.appraisedValue = newValue;
        a.appraisedAt = block.timestamp;
        a.documentHash = documentHash;

        emit AppraisalUpdated(tokenId, oldValue, newValue, documentHash);
    }

    /// @notice Toutes les informations d'un actif. Échoue si le jeton n'existe pas.
    function getAsset(uint256 tokenId) external view returns (Asset memory) {
        _requireOwned(tokenId);
        return _assets[tokenId];
    }

    /// @notice Valeur expertisée et date de l'expertise. Renvoie (0, 0) si le jeton n'existe pas.
    /// @dev Lu par l'oracle, qui rejette lui-même une expertise absente ou périmée.
    function appraisalOf(uint256 tokenId) external view returns (uint256 value, uint256 appraisedAt) {
        Asset storage a = _assets[tokenId];
        return (a.appraisedValue, a.appraisedAt);
    }

    /// @notice Identifiants des jetons détenus par une adresse.
    /// @dev Parcourt tous les jetons émis : suffisant pour une démonstration, à remplacer par
    ///      ERC721Enumerable si la collection devenait grande.
    function tokensOf(address holder) external view returns (uint256[] memory tokenIds) {
        uint256 count = balanceOf(holder);
        tokenIds = new uint256[](count);
        uint256 found = 0;
        for (uint256 id = 1; id < nextTokenId && found < count; ++id) {
            if (_ownerOf(id) == holder) tokenIds[found++] = id;
        }
    }

    function _setIssuer(address newIssuer) private {
        if (newIssuer == address(0)) revert ZeroAddress();
        emit IssuerChanged(issuer, newIssuer);
        issuer = newIssuer;
    }
}
