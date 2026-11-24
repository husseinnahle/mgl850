// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title InterestRateModel
/// @notice Modèle de taux d'intérêt linéaire par morceaux (EF-22 à EF-24, EF-26).
/// @dev Tous les taux sont annuels, sur 18 décimales : 1e18 = 100 %, 0.05e18 = 5 %.
///
///      Le taux d'emprunt dépend du taux d'utilisation U du pool (part des fonds qui est empruntée) :
///        - de U = 0 au point d'inflexion (`kink`), il monte doucement de `baseRate` à `baseRate + slope1` ;
///        - du point d'inflexion à U = 100 %, il monte vite, jusqu'à `baseRate + slope1 + slope2`.
///      Quand le pool est presque vide, emprunter devient cher et déposer devient rentable :
///      les emprunteurs remboursent, les prêteurs déposent, et la liquidité revient.
contract InterestRateModel is Ownable {
    uint256 public constant WAD = 1e18;

    /// @notice Plafond du taux d'emprunt à U = 100 %, pour rejeter une erreur de saisie.
    uint256 public constant MAX_TOTAL_RATE = 10e18;

    /// @notice Taux d'emprunt quand rien n'est emprunté.
    uint256 public baseRate;

    /// @notice Hausse du taux entre U = 0 et le point d'inflexion.
    uint256 public slope1;

    /// @notice Hausse du taux entre le point d'inflexion et U = 100 %.
    uint256 public slope2;

    /// @notice Point d'inflexion : taux d'utilisation à partir duquel la pente devient forte.
    uint256 public kink;

    /// @notice Part des intérêts payés par les emprunteurs qui alimente la réserve du protocole.
    uint256 public reserveFactor;

    event ParametersUpdated(uint256 baseRate, uint256 slope1, uint256 slope2, uint256 kink, uint256 reserveFactor);

    error InvalidKink();
    error InvalidReserveFactor();
    error RateTooHigh();

    constructor(
        address owner_,
        uint256 baseRate_,
        uint256 slope1_,
        uint256 slope2_,
        uint256 kink_,
        uint256 reserveFactor_
    ) Ownable(owner_) {
        _setParameters(baseRate_, slope1_, slope2_, kink_, reserveFactor_);
    }

    /// @notice Configure le taux de base, les pentes, le point d'inflexion et le facteur de réserve (EF-26).
    function setParameters(uint256 baseRate_, uint256 slope1_, uint256 slope2_, uint256 kink_, uint256 reserveFactor_)
        external
        onlyOwner
    {
        _setParameters(baseRate_, slope1_, slope2_, kink_, reserveFactor_);
    }

    /// @notice Taux d'utilisation du pool (EF-22) : emprunts / (liquidité + emprunts - réserve).
    /// @param cash Actif disponible dans le pool.
    /// @param borrows Total emprunté, intérêts compris.
    /// @param reserves Réserve du protocole, qui n'appartient pas aux prêteurs.
    function utilization(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256) {
        if (borrows == 0) return 0;
        uint256 total = cash + borrows;
        if (total <= reserves) return WAD;
        uint256 u = (borrows * WAD) / (total - reserves);
        return u > WAD ? WAD : u;
    }

    /// @notice Taux d'emprunt annuel pour un taux d'utilisation donné (EF-23).
    function borrowRate(uint256 u) public view returns (uint256) {
        if (u > WAD) u = WAD;
        if (u <= kink) {
            return baseRate + (slope1 * u) / kink;
        }
        return baseRate + slope1 + (slope2 * (u - kink)) / (WAD - kink);
    }

    /// @notice Taux de dépôt annuel (EF-24) : taux d'emprunt x U x (1 - facteur de réserve).
    /// @dev Les prêteurs se partagent les intérêts payés sur la part empruntée (d'où « x U »),
    ///      moins la fraction qui va à la réserve.
    function supplyRate(uint256 u) public view returns (uint256) {
        if (u > WAD) u = WAD;
        return (borrowRate(u) * u * (WAD - reserveFactor)) / (WAD * WAD);
    }

    function _setParameters(uint256 baseRate_, uint256 slope1_, uint256 slope2_, uint256 kink_, uint256 reserveFactor_)
        private
    {
        if (kink_ == 0 || kink_ >= WAD) revert InvalidKink();
        if (reserveFactor_ > WAD) revert InvalidReserveFactor();
        if (baseRate_ + slope1_ + slope2_ > MAX_TOTAL_RATE) revert RateTooHigh();

        baseRate = baseRate_;
        slope1 = slope1_;
        slope2 = slope2_;
        kink = kink_;
        reserveFactor = reserveFactor_;

        emit ParametersUpdated(baseRate_, slope1_, slope2_, kink_, reserveFactor_);
    }
}
