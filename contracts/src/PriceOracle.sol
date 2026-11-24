// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Ce que l'oracle lit dans le contrat des jetons RWA.
interface IRwaAppraisal {
    function appraisalOf(uint256 tokenId) external view returns (uint256 value, uint256 appraisedAt);
}

/// @title PriceOracle
/// @notice Oracle de prix simulé (EF-27 à EF-29, EF-40).
/// @dev Il fournit deux sortes de valeurs, toutes en USD sur 18 décimales :
///      - le prix d'un jeton ERC-20 entier, inscrit à la main par le propriétaire pour simuler le marché ;
///      - la valeur expertisée d'un jeton RWA, lue dans le contrat RWANFT.
///      Chaque valeur est horodatée. Les fonctions `get...` rejettent une valeur absente ou périmée :
///      toute opération du protocole qui en dépend échoue donc avec elles. Les fonctions `...Data`
///      ne rejettent rien et signalent la validité, pour que l'interface puisse l'afficher.
contract PriceOracle is Ownable {
    struct PriceData {
        uint256 price;
        uint256 updatedAt;
    }

    /// @notice Contrat des jetons RWA dont l'oracle lit les expertises.
    IRwaAppraisal public immutable rwaNft;

    /// @notice Durée de validité d'un prix ERC-20, en secondes.
    uint256 public maxPriceAge;

    /// @notice Durée de validité d'une expertise RWA, en secondes.
    uint256 public maxAppraisalAge;

    mapping(address token => PriceData) private _prices;

    event PriceUpdated(address indexed token, uint256 oldPrice, uint256 newPrice, uint256 updatedAt);
    event MaxAgesUpdated(uint256 maxPriceAge, uint256 maxAppraisalAge);

    error ZeroAddress();
    error ZeroPrice();
    error ZeroDuration();
    error PriceNotSet(address token);
    error StalePrice(address token, uint256 updatedAt);
    error AppraisalNotSet(uint256 tokenId);
    error StaleAppraisal(uint256 tokenId, uint256 appraisedAt);

    constructor(address owner_, address rwaNft_, uint256 maxPriceAge_, uint256 maxAppraisalAge_) Ownable(owner_) {
        if (rwaNft_ == address(0)) revert ZeroAddress();
        rwaNft = IRwaAppraisal(rwaNft_);
        _setMaxAges(maxPriceAge_, maxAppraisalAge_);
    }

    /// @notice Inscrit le prix d'un jeton ERC-20 (EF-28). Une valeur nulle est rejetée (EF-29).
    /// @param token Adresse du jeton.
    /// @param price Prix en USD d'un jeton entier, sur 18 décimales. Exemple : 2000e18 pour 2 000 $.
    function setPrice(address token, uint256 price) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (price == 0) revert ZeroPrice();

        uint256 oldPrice = _prices[token].price;
        _prices[token] = PriceData({price: price, updatedAt: block.timestamp});

        emit PriceUpdated(token, oldPrice, price, block.timestamp);
    }

    /// @notice Règle les durées de validité des prix et des expertises.
    function setMaxAges(uint256 maxPriceAge_, uint256 maxAppraisalAge_) external onlyOwner {
        _setMaxAges(maxPriceAge_, maxAppraisalAge_);
    }

    /// @notice Prix actuel d'un jeton ERC-20 (EF-27). Échoue si le prix est absent ou périmé.
    function getPrice(address token) external view returns (uint256) {
        PriceData memory data = _prices[token];
        if (data.price == 0) revert PriceNotSet(token);
        if (block.timestamp - data.updatedAt > maxPriceAge) revert StalePrice(token, data.updatedAt);
        return data.price;
    }

    /// @notice Prix d'un jeton, date de sa mise à jour et validité. Ne rejette jamais.
    function priceData(address token) external view returns (uint256 price, uint256 updatedAt, bool valid) {
        PriceData memory data = _prices[token];
        price = data.price;
        updatedAt = data.updatedAt;
        valid = price != 0 && block.timestamp - updatedAt <= maxPriceAge;
    }

    /// @notice Valeur expertisée d'un jeton RWA et date de l'expertise (EF-40).
    ///         Échoue si l'expertise est absente ou périmée.
    function getRwaValue(uint256 tokenId) external view returns (uint256 value, uint256 appraisedAt) {
        (value, appraisedAt) = rwaNft.appraisalOf(tokenId);
        if (value == 0) revert AppraisalNotSet(tokenId);
        if (block.timestamp - appraisedAt > maxAppraisalAge) revert StaleAppraisal(tokenId, appraisedAt);
    }

    /// @notice Valeur expertisée d'un jeton RWA, date de l'expertise et validité. Ne rejette jamais.
    function rwaValueData(uint256 tokenId) external view returns (uint256 value, uint256 appraisedAt, bool valid) {
        (value, appraisedAt) = rwaNft.appraisalOf(tokenId);
        valid = value != 0 && block.timestamp - appraisedAt <= maxAppraisalAge;
    }

    function _setMaxAges(uint256 maxPriceAge_, uint256 maxAppraisalAge_) private {
        if (maxPriceAge_ == 0 || maxAppraisalAge_ == 0) revert ZeroDuration();
        maxPriceAge = maxPriceAge_;
        maxAppraisalAge = maxAppraisalAge_;
        emit MaxAgesUpdated(maxPriceAge_, maxAppraisalAge_);
    }
}
