// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PriceOracle} from "./PriceOracle.sol";
import {InterestRateModel} from "./InterestRateModel.sol";

/// @title LendingPool
/// @notice Contrat principal du protocole de prêt décentralisé. Il garde les fonds et applique
///         toutes les règles : dépôts, garanties, emprunts, intérêts, facteur de santé,
///         liquidations et rachats des garanties RWA.
///
/// @dev Vue d'ensemble, à lire avant le code.
///
///  UN SEUL MARCHÉ. Les prêteurs déposent `asset` (tUSDC) ; les emprunteurs empruntent ce même actif.
///  Deux garanties sont acceptées :
///    - `collateralToken` (tETH), garantie fongible : une position par emprunteur ;
///    - un jeton `rwaNft`, actif réel tokenisé : une position par jeton, avec sa propre dette,
///      séparée de la position tETH du même emprunteur.
///
///  UNITÉS. Les montants sont dans la plus petite unité du jeton (6 décimales pour tUSDC,
///  18 pour tETH). Les valeurs en USD, les taux, les pourcentages et le facteur de santé sont
///  sur 18 décimales : 1e18 vaut 1 $, 100 % ou un facteur de santé de 1.
///
///  PARTS DES PRÊTEURS. Un dépôt donne des parts du pool. La valeur d'une part suit
///  (liquidité + emprunts - réserve) / parts : elle monte quand les emprunteurs paient des intérêts,
///  sans aucune transaction du prêteur (EF-12). Le pool retient aussi le capital versé par chaque
///  prêteur : l'écart avec la valeur de ses parts donne ses intérêts générés (EF-02).
///
///  DETTE NORMALISÉE. Le pool ne stocke pas la dette en jetons mais la dette divisée par
///  `borrowIndex` au moment de l'emprunt. `borrowIndex` part de 1 et grossit avec les intérêts :
///  dette actuelle = dette normalisée x `borrowIndex`. Une seule variable fait ainsi croître
///  toutes les dettes à la fois (EF-25).
///
///  ARRONDIS. Ils sont toujours en faveur du pool : une dette s'arrondit vers le haut,
///  ce que le pool remet s'arrondit vers le bas.
contract LendingPool is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // ---------------------------------------------------------------------
    // Paramètres du protocole (18 décimales : 0.75e18 = 75 %)
    // ---------------------------------------------------------------------

    uint256 public constant WAD = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Emprunt maximal contre une garantie fongible : 75 % de sa valeur (EF-17).
    uint256 public constant LTV_FUNGIBLE = 0.75e18;
    /// @notice Seuil de liquidation d'une garantie fongible : 80 % (EF-30).
    uint256 public constant LIQUIDATION_THRESHOLD_FUNGIBLE = 0.8e18;
    /// @notice Emprunt maximal contre une garantie RWA : 50 % de la valeur expertisée (EF-41).
    uint256 public constant LTV_RWA = 0.5e18;
    /// @notice Seuil de liquidation d'une garantie RWA : 60 % (EF-42).
    uint256 public constant LIQUIDATION_THRESHOLD_RWA = 0.6e18;
    /// @notice Part maximale de la dette qu'une liquidation peut rembourser : 50 % (EF-33).
    uint256 public constant CLOSE_FACTOR = 0.5e18;
    /// @notice Bonus du liquidateur d'une garantie fongible : 5 % (EF-34).
    uint256 public constant LIQUIDATION_BONUS = 0.05e18;
    /// @notice Rabais accordé à celui qui rachète une garantie RWA : 5 % (EF-43).
    uint256 public constant RWA_BUYOUT_DISCOUNT = 0.05e18;

    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    struct RwaPosition {
        address owner; // emprunteur qui a déposé le jeton
        uint256 scaledDebt; // dette normalisée de cette position
    }

    /// @notice État du pool, pour le tableau de bord (EF-01, EF-04).
    struct PoolState {
        uint256 totalLiquidity; // fonds des prêteurs, intérêts compris (actif)
        uint256 availableLiquidity; // actif disponible pour un emprunt ou un retrait
        uint256 totalBorrows; // total emprunté, intérêts compris (actif)
        uint256 totalReserves; // réserve du protocole (actif)
        uint256 utilization; // taux d'utilisation
        uint256 borrowRate; // taux d'emprunt annuel
        uint256 supplyRate; // taux de dépôt annuel
        uint256 assetPrice; // prix de l'actif emprunté (USD)
        uint256 collateralPrice; // prix de la garantie fongible (USD)
        bool pricesValid; // faux si un prix est absent ou périmé
    }

    /// @notice Position d'un utilisateur : dépôt de prêteur et position à garantie fongible (EF-02, EF-03).
    struct AccountPosition {
        uint256 deposited; // dépôt du prêteur, intérêts compris : ce qu'il peut retirer (actif)
        uint256 principal; // capital versé et encore dans le pool, sans les intérêts (actif)
        uint256 interestEarned; // intérêts générés et pas encore retirés (actif)
        uint256 collateral; // garantie déposée (jeton de garantie)
        uint256 debt; // dette, intérêts compris (actif)
        uint256 collateralValue; // valeur de la garantie (USD)
        uint256 debtValue; // valeur de la dette (USD)
        uint256 availableToBorrow; // montant encore empruntable (actif)
        uint256 healthFactor; // facteur de santé ; type(uint256).max sans dette
        uint256 liquidationPrice; // prix de la garantie sous lequel la position devient liquidable (USD)
        uint256 maxLiquidationRepay; // montant maximal qu'un liquidateur peut rembourser (actif)
        bool liquidatable; // vrai si le facteur de santé est inférieur à 1
    }

    /// @notice Position adossée à un jeton RWA (EF-47).
    struct RwaPositionInfo {
        address owner; // emprunteur ; adresse nulle si le jeton n'est pas déposé
        uint256 debt; // dette, intérêts compris (actif)
        uint256 debtValue; // valeur de la dette (USD)
        uint256 appraisedValue; // valeur expertisée (USD)
        uint256 appraisedAt; // date de l'expertise
        bool appraisalValid; // faux si l'expertise est absente ou périmée
        uint256 availableToBorrow; // montant encore empruntable (actif)
        uint256 healthFactor; // facteur de santé ; type(uint256).max sans dette
        uint256 buyoutPrice; // montant à verser pour racheter le jeton (actif)
        uint256 liquidatorGain; // gain estimé du liquidateur (USD)
        bool liquidatable; // vrai si le facteur de santé est inférieur à 1
    }

    // ---------------------------------------------------------------------
    // État
    // ---------------------------------------------------------------------

    /// @notice Actif prêté et emprunté (tUSDC).
    IERC20 public immutable asset;
    /// @notice Garantie fongible (tETH).
    IERC20 public immutable collateralToken;
    /// @notice Collection des actifs réels tokenisés.
    IERC721 public immutable rwaNft;
    PriceOracle public immutable oracle;
    InterestRateModel public immutable rateModel;

    uint256 private immutable _assetUnit; // 10 ** décimales de l'actif
    uint256 private immutable _collateralUnit; // 10 ** décimales de la garantie

    /// @notice Nombre total de parts détenues par les prêteurs.
    uint256 public totalShares;
    /// @notice Parts du pool détenues par chaque prêteur.
    mapping(address user => uint256) public sharesOf;
    /// @notice Capital versé par chaque prêteur et encore dans le pool, sans les intérêts (EF-02).
    ///         Un retrait le réduit dans la même proportion que les parts du prêteur.
    mapping(address user => uint256) public principalOf;

    /// @notice Actif disponible dans le pool. Suivi en interne : un jeton envoyé directement
    ///         au contrat, sans passer par `deposit`, ne modifie pas la valeur des parts.
    uint256 public totalCash;
    /// @notice Somme des dettes normalisées de toutes les positions.
    uint256 public totalScaledDebt;
    /// @notice Réserve du protocole : la part des intérêts qui ne revient pas aux prêteurs.
    uint256 public totalReserves;
    /// @notice Indice de la dette : part de 1e18 et grossit avec les intérêts.
    uint256 public borrowIndex = WAD;
    /// @notice Horodatage du dernier calcul des intérêts.
    uint256 public lastAccrual;

    /// @notice Garantie fongible déposée par chaque emprunteur.
    mapping(address user => uint256) public collateralOf;
    /// @notice Dette normalisée de la position à garantie fongible de chaque emprunteur.
    mapping(address user => uint256) public scaledDebtOf;

    mapping(uint256 tokenId => RwaPosition) private _rwaPositions;

    // Listes tenues à jour pour que l'interface affiche les positions sans relire tous les événements.
    EnumerableSet.AddressSet private _borrowers; // adresses ayant une dette à garantie fongible
    EnumerableSet.UintSet private _rwaTokenIds; // jetons RWA déposés en garantie

    // ---------------------------------------------------------------------
    // Événements (EF-05)
    // ---------------------------------------------------------------------

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed liquidator, address indexed borrower, uint256 repaid, uint256 collateralSeized);
    event RwaDeposited(address indexed user, uint256 indexed tokenId);
    event RwaWithdrawn(address indexed user, uint256 indexed tokenId);
    event RwaBorrowed(address indexed user, uint256 indexed tokenId, uint256 amount);
    event RwaRepaid(address indexed user, uint256 indexed tokenId, uint256 amount);
    event RwaBoughtOut(
        address indexed liquidator,
        address indexed borrower,
        uint256 indexed tokenId,
        uint256 price,
        uint256 debtRepaid,
        uint256 refund,
        uint256 shortfall
    );
    event InterestAccrued(uint256 borrowIndex, uint256 totalBorrows, uint256 totalReserves);

    // ---------------------------------------------------------------------
    // Erreurs
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error InsufficientLiquidity();
    error InsufficientCollateral();
    error ExceedsBorrowLimit();
    error HealthFactorTooLow();
    error NoDebt();
    error PositionHealthy();
    error ExceedsCloseFactor();
    error RwaAlreadyDeposited();
    error NoRwaPosition();
    error NotPositionOwner();
    error DebtOutstanding();

    constructor(address asset_, address collateralToken_, address rwaNft_, address oracle_, address rateModel_) {
        if (
            asset_ == address(0) || collateralToken_ == address(0) || rwaNft_ == address(0) || oracle_ == address(0)
                || rateModel_ == address(0)
        ) revert ZeroAddress();

        asset = IERC20(asset_);
        collateralToken = IERC20(collateralToken_);
        rwaNft = IERC721(rwaNft_);
        oracle = PriceOracle(oracle_);
        rateModel = InterestRateModel(rateModel_);
        _assetUnit = 10 ** IERC20Metadata(asset_).decimals();
        _collateralUnit = 10 ** IERC20Metadata(collateralToken_).decimals();
        lastAccrual = block.timestamp;
    }

    // ---------------------------------------------------------------------
    // Prêteur (EF-11 à EF-14)
    // ---------------------------------------------------------------------

    /// @notice Dépose des fonds dans le pool pour générer des intérêts (UC04).
    /// @dev L'appelant doit d'abord approuver le pool sur le jeton `asset`.
    ///      Le pool n'a qu'un actif prêtable : aucun autre jeton ne peut être déposé ici.
    /// @param amount Montant à déposer. Un montant nul est rejeté (EF-11).
    /// @return shares Parts du pool reçues.
    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        _accrue();

        uint256 liquidity = _liquidity(borrowIndex, totalReserves);
        shares = (totalShares == 0 || liquidity == 0) ? amount : Math.mulDiv(amount, totalShares, liquidity);
        if (shares == 0) revert ZeroAmount();

        totalShares += shares;
        sharesOf[msg.sender] += shares;
        principalOf[msg.sender] += amount;
        totalCash += amount;

        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Retire tout ou une partie de son dépôt, intérêts compris (UC05, EF-13).
    /// @param amount Montant à retirer. `type(uint256).max` retire tout.
    /// @return withdrawn Montant réellement retiré.
    function withdraw(uint256 amount) external nonReentrant returns (uint256 withdrawn) {
        if (amount == 0) revert ZeroAmount();
        _accrue();

        uint256 userShares = sharesOf[msg.sender];
        if (userShares == 0) revert InsufficientBalance();

        uint256 liquidity = _liquidity(borrowIndex, totalReserves);
        uint256 shares;
        if (amount == type(uint256).max) {
            shares = userShares;
            withdrawn = Math.mulDiv(shares, liquidity, totalShares);
        } else {
            if (liquidity == 0) revert InsufficientLiquidity();
            withdrawn = amount;
            shares = Math.mulDiv(amount, totalShares, liquidity, Math.Rounding.Ceil);
            if (shares > userShares) revert InsufficientBalance();
        }
        if (withdrawn == 0) revert ZeroAmount();
        // EF-14 : on ne peut pas retirer des fonds qui sont actuellement prêtés
        if (withdrawn > totalCash) revert InsufficientLiquidity();

        // Le retrait reprend capital et intérêts dans la même proportion : celle des parts rendues.
        principalOf[msg.sender] -= Math.mulDiv(principalOf[msg.sender], shares, userShares);
        sharesOf[msg.sender] = userShares - shares;
        totalShares -= shares;
        totalCash -= withdrawn;

        asset.safeTransfer(msg.sender, withdrawn);
        emit Withdrawn(msg.sender, withdrawn, shares);
    }

    // ---------------------------------------------------------------------
    // Emprunteur, garantie fongible (EF-16 à EF-21)
    // ---------------------------------------------------------------------

    /// @notice Dépose une garantie fongible (UC06). Elle est comptée à part des dépôts de prêteur (EF-16).
    /// @dev L'appelant doit d'abord approuver le pool sur le jeton `collateralToken`.
    function depositCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        collateralOf[msg.sender] += amount;

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        emit CollateralDeposited(msg.sender, amount);
    }

    /// @notice Retire une partie de sa garantie, tant que la position reste saine (EF-21).
    function withdrawCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrue();

        uint256 balance = collateralOf[msg.sender];
        if (amount > balance) revert InsufficientCollateral();
        uint256 remaining = balance - amount;
        collateralOf[msg.sender] = remaining;

        // Sans dette, aucun prix n'est nécessaire : le retrait reste possible même si l'oracle est périmé.
        uint256 scaled = scaledDebtOf[msg.sender];
        if (scaled != 0) {
            uint256 collateralValue = _collateralValue(remaining, oracle.getPrice(address(collateralToken)));
            uint256 debtValue = _assetValue(_debtOf(scaled, borrowIndex), oracle.getPrice(address(asset)));
            if (_healthFactor(collateralValue, LIQUIDATION_THRESHOLD_FUNGIBLE, debtValue) < WAD) {
                revert HealthFactorTooLow();
            }
        }

        collateralToken.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /// @notice Emprunte contre sa garantie fongible, jusqu'à 75 % de sa valeur (UC07, EF-17, EF-18).
    /// @dev Comme la limite d'emprunt (75 %) est sous le seuil de liquidation (80 %), un emprunt
    ///      accepté laisse toujours un facteur de santé supérieur à 1.
    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrue();
        if (amount > totalCash) revert InsufficientLiquidity();

        uint256 scaledAdded = Math.mulDiv(amount, WAD, borrowIndex, Math.Rounding.Ceil);
        uint256 newScaled = scaledDebtOf[msg.sender] + scaledAdded;

        uint256 collateralValue = _collateralValue(collateralOf[msg.sender], oracle.getPrice(address(collateralToken)));
        uint256 debtValue = _assetValue(_debtOf(newScaled, borrowIndex), oracle.getPrice(address(asset)));
        if (debtValue > Math.mulDiv(collateralValue, LTV_FUNGIBLE, WAD)) revert ExceedsBorrowLimit();

        scaledDebtOf[msg.sender] = newScaled;
        totalScaledDebt += scaledAdded;
        totalCash -= amount;
        _borrowers.add(msg.sender);

        asset.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    /// @notice Rembourse tout ou une partie de sa dette, intérêts compris (UC08, EF-20).
    /// @param amount Montant à rembourser. Un montant supérieur à la dette, par exemple
    ///        `type(uint256).max`, rembourse exactement toute la dette.
    /// @return repaid Montant réellement prélevé.
    function repay(uint256 amount) external nonReentrant returns (uint256 repaid) {
        _accrue();

        uint256 scaled = scaledDebtOf[msg.sender];
        uint256 scaledRepaid;
        (repaid, scaledRepaid) = _repayAmounts(scaled, amount);

        scaledDebtOf[msg.sender] = scaled - scaledRepaid;
        totalScaledDebt -= scaledRepaid;
        totalCash += repaid;
        if (scaledRepaid == scaled) _borrowers.remove(msg.sender);

        asset.safeTransferFrom(msg.sender, address(this), repaid);
        emit Repaid(msg.sender, repaid);
    }

    // ---------------------------------------------------------------------
    // Liquidation d'une position à garantie fongible (EF-32 à EF-35)
    // ---------------------------------------------------------------------

    /// @notice Liquide une position dont le facteur de santé est inférieur à 1 (UC09 à UC11).
    /// @dev Le liquidateur rembourse au plus 50 % de la dette et reçoit la garantie correspondante,
    ///      majorée d'un bonus de 5 %. Tout se passe dans la même transaction.
    /// @param borrower Emprunteur dont la position est liquidée.
    /// @param repayAmount Montant de la dette remboursé par le liquidateur.
    /// @return collateralSeized Garantie remise au liquidateur.
    function liquidate(address borrower, uint256 repayAmount) external nonReentrant returns (uint256 collateralSeized) {
        if (repayAmount == 0) revert ZeroAmount();
        _accrue();

        uint256 scaled = scaledDebtOf[borrower];
        if (scaled == 0) revert NoDebt();
        uint256 debt = _debtOf(scaled, borrowIndex);
        uint256 collateral = collateralOf[borrower];
        uint256 assetPrice = oracle.getPrice(address(asset));
        uint256 collateralPrice = oracle.getPrice(address(collateralToken));

        // EF-31, EF-35 : une position saine ne peut pas être liquidée
        if (
            _healthFactor(
                    _collateralValue(collateral, collateralPrice),
                    LIQUIDATION_THRESHOLD_FUNGIBLE,
                    _assetValue(debt, assetPrice)
                ) >= WAD
        ) revert PositionHealthy();

        // EF-33 : au plus 50 % de la dette par liquidation
        if (repayAmount > Math.mulDiv(debt, CLOSE_FACTOR, WAD)) revert ExceedsCloseFactor();

        // EF-34 : garantie équivalente à la dette remboursée, majorée de 5 %
        collateralSeized = _seizeAmount(_assetValue(repayAmount, assetPrice), collateralPrice);
        // EF-35 : la garantie à remettre ne peut pas dépasser la garantie fournie
        if (collateralSeized > collateral) revert InsufficientCollateral();

        uint256 scaledRepaid = Math.mulDiv(repayAmount, WAD, borrowIndex);
        if (scaledRepaid == 0) revert ZeroAmount();

        scaledDebtOf[borrower] = scaled - scaledRepaid;
        totalScaledDebt -= scaledRepaid;
        totalCash += repayAmount;
        collateralOf[borrower] = collateral - collateralSeized;

        // EF-35 : ce transfert échoue si le liquidateur n'a pas les fonds
        asset.safeTransferFrom(msg.sender, address(this), repayAmount);
        collateralToken.safeTransfer(msg.sender, collateralSeized);
        emit Liquidated(msg.sender, borrower, repayAmount, collateralSeized);
    }

    // ---------------------------------------------------------------------
    // Garantie sous forme d'actif réel tokenisé (EF-39 à EF-46)
    // ---------------------------------------------------------------------

    /// @notice Dépose un jeton RWA en garantie (UC18, EF-39). Ouvre une position propre à ce jeton.
    /// @dev L'appelant doit d'abord approuver le pool sur le jeton (approbation ERC-721).
    function depositRwa(uint256 tokenId) external nonReentrant {
        if (_rwaPositions[tokenId].owner != address(0)) revert RwaAlreadyDeposited();

        _rwaPositions[tokenId] = RwaPosition({owner: msg.sender, scaledDebt: 0});
        _rwaTokenIds.add(tokenId);

        rwaNft.transferFrom(msg.sender, address(this), tokenId);
        emit RwaDeposited(msg.sender, tokenId);
    }

    /// @notice Reprend son jeton RWA une fois la dette entièrement remboursée (UC19, EF-39, EF-46).
    function withdrawRwa(uint256 tokenId) external nonReentrant {
        RwaPosition memory pos = _rwaPositions[tokenId];
        if (pos.owner != msg.sender) revert NotPositionOwner();
        if (pos.scaledDebt != 0) revert DebtOutstanding();

        delete _rwaPositions[tokenId];
        _rwaTokenIds.remove(tokenId);

        rwaNft.transferFrom(address(this), msg.sender, tokenId);
        emit RwaWithdrawn(msg.sender, tokenId);
    }

    /// @notice Emprunte contre un jeton RWA déposé, jusqu'à 50 % de sa valeur expertisée (EF-41).
    /// @dev L'emprunt échoue si l'expertise est absente ou périmée (EF-40).
    function borrowAgainstRwa(uint256 tokenId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        RwaPosition storage pos = _rwaPositions[tokenId];
        if (pos.owner != msg.sender) revert NotPositionOwner();
        _accrue();
        if (amount > totalCash) revert InsufficientLiquidity();

        uint256 scaledAdded = Math.mulDiv(amount, WAD, borrowIndex, Math.Rounding.Ceil);
        uint256 newScaled = pos.scaledDebt + scaledAdded;

        (uint256 appraisedValue,) = oracle.getRwaValue(tokenId);
        uint256 debtValue = _assetValue(_debtOf(newScaled, borrowIndex), oracle.getPrice(address(asset)));
        if (debtValue > Math.mulDiv(appraisedValue, LTV_RWA, WAD)) revert ExceedsBorrowLimit();

        pos.scaledDebt = newScaled;
        totalScaledDebt += scaledAdded;
        totalCash -= amount;

        asset.safeTransfer(msg.sender, amount);
        emit RwaBorrowed(msg.sender, tokenId, amount);
    }

    /// @notice Rembourse tout ou une partie de la dette adossée à un jeton RWA.
    /// @param amount Montant à rembourser. Un montant supérieur à la dette, par exemple
    ///        `type(uint256).max`, rembourse exactement toute la dette.
    /// @return repaid Montant réellement prélevé.
    function repayRwa(uint256 tokenId, uint256 amount) external nonReentrant returns (uint256 repaid) {
        RwaPosition storage pos = _rwaPositions[tokenId];
        if (pos.owner != msg.sender) revert NotPositionOwner();
        _accrue();

        uint256 scaled = pos.scaledDebt;
        uint256 scaledRepaid;
        (repaid, scaledRepaid) = _repayAmounts(scaled, amount);

        pos.scaledDebt = scaled - scaledRepaid;
        totalScaledDebt -= scaledRepaid;
        totalCash += repaid;

        asset.safeTransferFrom(msg.sender, address(this), repaid);
        emit RwaRepaid(msg.sender, tokenId, repaid);
    }

    /// @notice Rachète la garantie d'une position RWA liquidable (UC20, EF-43 à EF-46).
    /// @dev Un jeton non fongible ne se divise pas : la liquidation est un rachat du jeton entier.
    ///      Le liquidateur verse la valeur expertisée moins 5 %. Dans la même transaction, le pool
    ///      se rembourse de la dette, remet le solde à l'emprunteur et transfère le jeton (EF-44).
    ///      Si le montant versé ne couvre pas la dette, l'écart est imputé à la réserve (EF-45).
    /// @return price Montant versé par le liquidateur.
    function buyoutRwa(uint256 tokenId) external nonReentrant returns (uint256 price) {
        RwaPosition memory pos = _rwaPositions[tokenId];
        if (pos.owner == address(0)) revert NoRwaPosition();
        _accrue();

        uint256 debt = _debtOf(pos.scaledDebt, borrowIndex);
        {
            (uint256 appraisedValue,) = oracle.getRwaValue(tokenId);
            uint256 assetPrice = oracle.getPrice(address(asset));
            // EF-46 : une position saine ne peut pas être rachetée
            if (_healthFactor(appraisedValue, LIQUIDATION_THRESHOLD_RWA, _assetValue(debt, assetPrice)) >= WAD) {
                revert PositionHealthy();
            }
            price = _valueToAsset(
                Math.mulDiv(appraisedValue, WAD - RWA_BUYOUT_DISCOUNT, WAD), assetPrice, Math.Rounding.Ceil
            );
        }

        uint256 debtRepaid = Math.min(price, debt);
        uint256 refund = price - debtRepaid; // solde remis à l'emprunteur
        uint256 shortfall = debt - debtRepaid; // part de la dette que le rachat ne couvre pas

        // La réserve absorbe l'écart. Si elle ne suffit pas, le reste est supporté par les
        // prêteurs : la valeur de leurs parts baisse d'autant.
        if (shortfall != 0) totalReserves -= Math.min(shortfall, totalReserves);

        totalScaledDebt -= pos.scaledDebt;
        totalCash += debtRepaid;
        delete _rwaPositions[tokenId];
        _rwaTokenIds.remove(tokenId);

        asset.safeTransferFrom(msg.sender, address(this), price);
        if (refund != 0) asset.safeTransfer(pos.owner, refund);
        rwaNft.transferFrom(address(this), msg.sender, tokenId);
        emit RwaBoughtOut(msg.sender, pos.owner, tokenId, price, debtRepaid, refund, shortfall);
    }

    // ---------------------------------------------------------------------
    // Intérêts (EF-25)
    // ---------------------------------------------------------------------

    /// @notice Met à jour les intérêts jusqu'au bloc courant (UC12, UC13).
    /// @dev Appelé automatiquement au début de chaque opération. N'importe qui peut aussi l'appeler.
    function accrueInterest() external {
        _accrue();
    }

    // ---------------------------------------------------------------------
    // Lectures pour l'interface
    // ---------------------------------------------------------------------
    // Ces fonctions tiennent compte des intérêts courus depuis la dernière opération, sans rien
    // écrire. Elles ne rejettent pas un prix périmé : elles l'utilisent et le signalent.

    /// @notice Total emprunté, intérêts compris.
    function totalBorrows() public view returns (uint256) {
        (uint256 index,) = _previewAccrual();
        return Math.mulDiv(totalScaledDebt, index, WAD);
    }

    /// @notice Fonds appartenant aux prêteurs, intérêts compris : liquidité + emprunts - réserve.
    function totalLiquidity() public view returns (uint256) {
        (uint256 index, uint256 reserves) = _previewAccrual();
        return _liquidity(index, reserves);
    }

    /// @notice État du pool pour le tableau de bord (UC01, EF-01, EF-04).
    function getPoolState() external view returns (PoolState memory s) {
        (uint256 index, uint256 reserves) = _previewAccrual();

        s.totalBorrows = Math.mulDiv(totalScaledDebt, index, WAD);
        s.totalReserves = reserves;
        s.totalLiquidity = _liquidity(index, reserves);
        s.availableLiquidity = totalCash;
        s.utilization = rateModel.utilization(totalCash, s.totalBorrows, reserves);
        s.borrowRate = rateModel.borrowRate(s.utilization);
        s.supplyRate = rateModel.supplyRate(s.utilization);

        bool assetValid;
        bool collateralValid;
        (s.assetPrice,, assetValid) = oracle.priceData(address(asset));
        (s.collateralPrice,, collateralValid) = oracle.priceData(address(collateralToken));
        s.pricesValid = assetValid && collateralValid;
    }

    /// @notice Position d'un utilisateur : dépôt de prêteur et position à garantie fongible
    ///         (UC02, UC03, EF-02, EF-03, EF-18, EF-36).
    function getAccountPosition(address user) external view returns (AccountPosition memory p) {
        (uint256 index, uint256 reserves) = _previewAccrual();
        (uint256 assetPrice,,) = oracle.priceData(address(asset));
        (uint256 collateralPrice,,) = oracle.priceData(address(collateralToken));

        if (totalShares != 0) {
            p.deposited = Math.mulDiv(sharesOf[user], _liquidity(index, reserves), totalShares);
        }
        p.principal = principalOf[user];
        // Les intérêts restent à zéro si le dépôt vaut moins que le capital : arrondi d'une unité,
        // ou perte supportée par les prêteurs après un rachat RWA qui ne couvre pas la dette.
        if (p.deposited > p.principal) p.interestEarned = p.deposited - p.principal;
        p.collateral = collateralOf[user];
        p.debt = _debtOf(scaledDebtOf[user], index);
        p.collateralValue = _collateralValue(p.collateral, collateralPrice);
        p.debtValue = _assetValue(p.debt, assetPrice);
        p.healthFactor = _healthFactor(p.collateralValue, LIQUIDATION_THRESHOLD_FUNGIBLE, p.debtValue);
        p.liquidatable = p.healthFactor < WAD;

        uint256 borrowLimit = Math.mulDiv(p.collateralValue, LTV_FUNGIBLE, WAD);
        if (borrowLimit > p.debtValue && assetPrice != 0) {
            p.availableToBorrow =
                Math.min(_valueToAsset(borrowLimit - p.debtValue, assetPrice, Math.Rounding.Floor), totalCash);
        }
        if (p.debt != 0 && p.collateral != 0) {
            // Prix de la garantie pour lequel le facteur de santé vaut exactement 1.
            p.liquidationPrice = Math.mulDiv(
                p.debtValue, _collateralUnit * WAD, p.collateral * LIQUIDATION_THRESHOLD_FUNGIBLE, Math.Rounding.Ceil
            );
        }
        if (p.liquidatable) p.maxLiquidationRepay = Math.mulDiv(p.debt, CLOSE_FACTOR, WAD);
    }

    /// @notice Position adossée à un jeton RWA (EF-47). `owner` est l'adresse nulle si le jeton
    ///         n'est pas déposé en garantie.
    function getRwaPosition(uint256 tokenId) external view returns (RwaPositionInfo memory p) {
        RwaPosition memory pos = _rwaPositions[tokenId];
        if (pos.owner == address(0)) return p;

        (uint256 index,) = _previewAccrual();
        (uint256 assetPrice,,) = oracle.priceData(address(asset));

        p.owner = pos.owner;
        p.debt = _debtOf(pos.scaledDebt, index);
        p.debtValue = _assetValue(p.debt, assetPrice);
        (p.appraisedValue, p.appraisedAt, p.appraisalValid) = oracle.rwaValueData(tokenId);
        p.healthFactor = _healthFactor(p.appraisedValue, LIQUIDATION_THRESHOLD_RWA, p.debtValue);
        p.liquidatable = p.healthFactor < WAD;

        if (assetPrice == 0) return p;

        uint256 borrowLimit = Math.mulDiv(p.appraisedValue, LTV_RWA, WAD);
        if (p.appraisalValid && borrowLimit > p.debtValue) {
            p.availableToBorrow =
                Math.min(_valueToAsset(borrowLimit - p.debtValue, assetPrice, Math.Rounding.Floor), totalCash);
        }
        uint256 buyoutValue = Math.mulDiv(p.appraisedValue, WAD - RWA_BUYOUT_DISCOUNT, WAD);
        p.buyoutPrice = _valueToAsset(buyoutValue, assetPrice, Math.Rounding.Ceil);
        p.liquidatorGain = p.appraisedValue - buyoutValue;
    }

    /// @notice Facteur de santé de la position à garantie fongible d'un utilisateur (EF-30).
    ///         Vaut `type(uint256).max` s'il n'a aucune dette.
    function healthFactor(address user) external view returns (uint256) {
        (uint256 index,) = _previewAccrual();
        (uint256 assetPrice,,) = oracle.priceData(address(asset));
        (uint256 collateralPrice,,) = oracle.priceData(address(collateralToken));
        return _healthFactor(
            _collateralValue(collateralOf[user], collateralPrice),
            LIQUIDATION_THRESHOLD_FUNGIBLE,
            _assetValue(_debtOf(scaledDebtOf[user], index), assetPrice)
        );
    }

    /// @notice Facteur de santé d'une position RWA (EF-42).
    function rwaHealthFactor(uint256 tokenId) external view returns (uint256) {
        (uint256 index,) = _previewAccrual();
        (uint256 assetPrice,,) = oracle.priceData(address(asset));
        (uint256 appraisedValue,,) = oracle.rwaValueData(tokenId);
        return _healthFactor(
            appraisedValue,
            LIQUIDATION_THRESHOLD_RWA,
            _assetValue(_debtOf(_rwaPositions[tokenId].scaledDebt, index), assetPrice)
        );
    }

    /// @notice Garantie que recevrait un liquidateur en remboursant `repayAmount`, aux prix actuels,
    ///         et valeur en USD de son bonus (EF-36).
    function previewLiquidation(uint256 repayAmount)
        external
        view
        returns (uint256 collateralSeized, uint256 bonusValue)
    {
        (uint256 assetPrice,,) = oracle.priceData(address(asset));
        (uint256 collateralPrice,,) = oracle.priceData(address(collateralToken));
        if (collateralPrice == 0) return (0, 0);

        uint256 repayValue = _assetValue(repayAmount, assetPrice);
        collateralSeized = _seizeAmount(repayValue, collateralPrice);
        bonusValue = Math.mulDiv(repayValue, LIQUIDATION_BONUS, WAD);
    }

    /// @notice Adresses qui ont une dette à garantie fongible. L'interface filtre ensuite avec
    ///         `getAccountPosition` pour trouver les positions liquidables.
    function getBorrowers() external view returns (address[] memory) {
        return _borrowers.values();
    }

    /// @notice Jetons RWA actuellement déposés en garantie.
    function getRwaTokenIds() external view returns (uint256[] memory) {
        return _rwaTokenIds.values();
    }

    // ---------------------------------------------------------------------
    // Fonctions internes
    // ---------------------------------------------------------------------

    /// @dev Intérêts courus depuis `lastAccrual`, sans rien écrire.
    ///      Entre deux opérations le taux est constant : il dépend du taux d'utilisation, qui ne
    ///      change qu'avec une opération. Intérêt de la période = taux annuel x durée / 1 an.
    function _previewAccrual() internal view returns (uint256 index, uint256 reserves) {
        index = borrowIndex;
        reserves = totalReserves;

        uint256 elapsed = block.timestamp - lastAccrual;
        if (elapsed == 0 || totalScaledDebt == 0) return (index, reserves);

        uint256 borrowsBefore = Math.mulDiv(totalScaledDebt, index, WAD);
        uint256 rate = rateModel.borrowRate(rateModel.utilization(totalCash, borrowsBefore, reserves));

        index += Math.mulDiv(index, rate * elapsed, SECONDS_PER_YEAR * WAD);

        uint256 interest = Math.mulDiv(totalScaledDebt, index, WAD) - borrowsBefore;
        reserves += Math.mulDiv(interest, rateModel.reserveFactor(), WAD);
    }

    function _accrue() internal {
        if (block.timestamp == lastAccrual) return;

        (uint256 index, uint256 reserves) = _previewAccrual();
        borrowIndex = index;
        totalReserves = reserves;
        lastAccrual = block.timestamp;

        emit InterestAccrued(index, Math.mulDiv(totalScaledDebt, index, WAD), reserves);
    }

    /// @dev Montants d'un remboursement : ce qui est prélevé et la dette normalisée effacée.
    function _repayAmounts(uint256 scaled, uint256 amount)
        internal
        view
        returns (uint256 repaid, uint256 scaledRepaid)
    {
        if (amount == 0) revert ZeroAmount();
        if (scaled == 0) revert NoDebt();

        uint256 debt = _debtOf(scaled, borrowIndex);
        if (amount >= debt) return (debt, scaled); // remboursement total

        scaledRepaid = Math.mulDiv(amount, WAD, borrowIndex);
        if (scaledRepaid == 0) revert ZeroAmount();
        repaid = amount;
    }

    /// @dev Fonds appartenant aux prêteurs.
    function _liquidity(uint256 index, uint256 reserves) internal view returns (uint256) {
        uint256 gross = totalCash + Math.mulDiv(totalScaledDebt, index, WAD);
        return gross > reserves ? gross - reserves : 0;
    }

    /// @dev Dette en actif à partir de la dette normalisée, arrondie vers le haut.
    function _debtOf(uint256 scaled, uint256 index) internal pure returns (uint256) {
        return Math.mulDiv(scaled, index, WAD, Math.Rounding.Ceil);
    }

    /// @dev Facteur de santé (EF-30) : valeur de la garantie x seuil de liquidation / valeur de la dette.
    function _healthFactor(uint256 collateralValue, uint256 threshold, uint256 debtValue)
        internal
        pure
        returns (uint256)
    {
        if (debtValue == 0) return type(uint256).max;
        return Math.mulDiv(collateralValue, threshold, debtValue);
    }

    /// @dev Garantie remise au liquidateur : valeur remboursée x (1 + bonus) / prix de la garantie.
    function _seizeAmount(uint256 repayValue, uint256 collateralPrice) internal view returns (uint256) {
        uint256 seizeValue = Math.mulDiv(repayValue, WAD + LIQUIDATION_BONUS, WAD);
        return Math.mulDiv(seizeValue, _collateralUnit, collateralPrice);
    }

    /// @dev Valeur en USD d'un montant d'actif.
    function _assetValue(uint256 amount, uint256 price) internal view returns (uint256) {
        return Math.mulDiv(amount, price, _assetUnit);
    }

    /// @dev Valeur en USD d'un montant de garantie fongible.
    function _collateralValue(uint256 amount, uint256 price) internal view returns (uint256) {
        return Math.mulDiv(amount, price, _collateralUnit);
    }

    /// @dev Montant d'actif correspondant à une valeur en USD.
    function _valueToAsset(uint256 value, uint256 price, Math.Rounding rounding) internal view returns (uint256) {
        return Math.mulDiv(value, _assetUnit, price, rounding);
    }
}
