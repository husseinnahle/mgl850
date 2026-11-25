# Protocole de prêt décentralisé : contrats

MGL850, automne 2026, Équipe 06. Ce dossier contient les contrats Solidity du protocole, leurs tests et les scripts de déploiement. L'interface web vit dans un dossier voisin et s'appuie sur la section [Interface pour le front](#interface-pour-le-front).

## En bref

| Contrat | Rôle |
|---|---|
| `LendingPool` | Contrat principal. Garde les fonds et applique toutes les règles : dépôts, garanties, emprunts, intérêts, facteur de santé, liquidations, rachats RWA. |
| `InterestRateModel` | Calcule le taux d'utilisation, le taux d'emprunt (linéaire par morceaux) et le taux de dépôt. |
| `PriceOracle` | Oracle simulé. Donne le prix des jetons ERC-20 et la valeur expertisée des jetons RWA, avec leur date. |
| `RWANFT` | Jeton ERC-721 qui représente un actif réel expertisé : maison, montre, bijou. |
| `TestToken` | Jeton ERC-20 de test, déployé deux fois : `tETH` (garantie, 18 décimales) et `tUSDC` (prêté et emprunté, 6 décimales). |

État au 22 novembre 2026 : 129 tests passent, 100 % des lignes et des fonctions sont couvertes, et les deux scénarios de démonstration ont été rejoués sur une chaîne locale Anvil. Les contrats sont déployés sur Sepolia : voir [Adresses sur Sepolia](#adresses-sur-sepolia).

## Adresses sur Sepolia

Déployés le 22 novembre 2026, aux blocs 12 190 035 à 12 190 042, par le compte `0xf5BB5dE6872C0D10a3beDAb43fA102FF87f71aA5`. Ce compte est propriétaire des jetons de test, de l'oracle et du modèle de taux, et émetteur des jetons RWA. Les mêmes adresses sont dans `deployments/11155111.json`.

| Contrat | Adresse | ABI |
|---|---|---|
| `LendingPool` | [`0xfaF58cd5DCA4C02CB71a0b2C9d1778A66E6C5D0d`](https://sepolia.etherscan.io/address/0xfaF58cd5DCA4C02CB71a0b2C9d1778A66E6C5D0d) | `abi/LendingPool.json` |
| `tUSDC` | [`0x36De40AC39406c79A89d21ef5D662FDC43E7Ab32`](https://sepolia.etherscan.io/address/0x36De40AC39406c79A89d21ef5D662FDC43E7Ab32) | `abi/TestToken.json` |
| `tETH` | [`0x334992731d73354DDFE0f411Df554aeE735Fea82`](https://sepolia.etherscan.io/address/0x334992731d73354DDFE0f411Df554aeE735Fea82) | `abi/TestToken.json` |
| `RWANFT` | [`0x9d01d6c4827C454A5e534cC98E6E4Fc550B3A68D`](https://sepolia.etherscan.io/address/0x9d01d6c4827C454A5e534cC98E6E4Fc550B3A68D) | `abi/RWANFT.json` |
| `PriceOracle` | [`0x9f7AFa6C7588b0A99183217723e5C29A413aa1b3`](https://sepolia.etherscan.io/address/0x9f7AFa6C7588b0A99183217723e5C29A413aa1b3) | `abi/PriceOracle.json` |
| `InterestRateModel` | [`0xD5A728e3CBaB9C97d58511CDa512Fba00dB4D01d`](https://sepolia.etherscan.io/address/0xD5A728e3CBaB9C97d58511CDa512Fba00dB4D01d) | `abi/InterestRateModel.json` |

Réseau : Sepolia, identifiant de chaîne `11155111`. Prix inscrits au déploiement : tETH à 2 000 $, tUSDC à 1 $. Ils seront périmés après le 22 décembre 2026 : les réinscrire avec `setPrice` avant la démonstration.

Pour obtenir des jetons de test, chaque compte appelle `faucet()` sur tUSDC et sur tETH. Il lui faut aussi un peu d'ETH Sepolia pour payer le gaz.

## Démarrage

Il faut [Foundry](https://getfoundry.sh) (`forge`, `cast`, `anvil`). Les bibliothèques sont déjà dans `lib/`, rien d'autre à installer.

```bash
forge build
```

```bash
forge test
```

```bash
forge coverage --no-match-coverage "(script|test)"
```

Pour lancer une seule famille de tests : `forge test --match-contract LendingPoolRwaTest`. Pour voir le détail d'un test : `forge test --match-test test_Liquidate -vvvv`.

## Paramètres du protocole

| Paramètre | Garantie fongible (tETH) | Garantie RWA |
|---|---|---|
| Emprunt maximal (LTV) | 75 % de la valeur | 50 % de la valeur expertisée |
| Seuil de liquidation | 80 % | 60 % |
| Liquidation | Au plus 50 % de la dette, bonus de 5 % | Rachat du jeton entier, rabais de 5 % |

Modèle de taux déployé par défaut : 2 % de base, +8 % jusqu'à 80 % d'utilisation, +100 % au-delà, 10 % des intérêts pour la réserve. L'administrateur peut les changer avec `InterestRateModel.setParameters`.

Facteur de santé = valeur de la garantie × seuil de liquidation ÷ valeur de la dette. Une position est liquidable quand il passe sous 1.

## Unités

C'est le point à ne pas rater dans l'interface.

| Grandeur | Unité | Exemple |
|---|---|---|
| Montant de `tUSDC` | 6 décimales | 15 000 tUSDC = `15000000000` |
| Montant de `tETH` | 18 décimales | 10 tETH = `10000000000000000000` |
| Valeur en USD, prix | 18 décimales | 2 000 $ = `2000e18` |
| Taux, pourcentage | 18 décimales, par an | 3,5 % = `0.035e18` |
| Facteur de santé | 18 décimales | 1,2 = `1.2e18` ; `type(uint256).max` s'il n'y a pas de dette |
| Dates | secondes Unix | |

Avec ethers.js : `formatUnits(x, 6)` pour un montant de tUSDC, `formatUnits(x, 18)` pour tout le reste.

## Interface pour le front

Deux choses à copier dans le projet web :

- `abi/` : l'ABI de chaque contrat, au format JSON (`LendingPool.json`, `PriceOracle.json`, `InterestRateModel.json`, `RWANFT.json`, `TestToken.json`). Pour les régénérer après un changement : `forge inspect LendingPool abi --json`.
- `deployments/<chainId>.json` : les adresses déployées et le bloc de déploiement. `31337` pour Anvil, `11155111` pour Sepolia.

### Lectures

Toutes ces fonctions tiennent déjà compte des intérêts courus. Elles ne rejettent jamais, même si un prix est périmé : elles le signalent.

| Fonction de `LendingPool` | Renvoie | Sert à |
|---|---|---|
| `getPoolState()` | `totalLiquidity`, `availableLiquidity`, `totalBorrows`, `totalReserves`, `utilization`, `borrowRate`, `supplyRate`, `assetPrice`, `collateralPrice`, `pricesValid` | Tableau de bord (EF-01, EF-04) |
| `getAccountPosition(user)` | `deposited`, `principal`, `interestEarned`, `collateral`, `debt`, `collateralValue`, `debtValue`, `availableToBorrow`, `healthFactor`, `liquidationPrice`, `maxLiquidationRepay`, `liquidatable` | Position de l'utilisateur, jauge de santé, montant maximal (EF-02, EF-03, EF-18) |
| `getRwaPosition(tokenId)` | `owner`, `debt`, `debtValue`, `appraisedValue`, `appraisedAt`, `appraisalValid`, `availableToBorrow`, `healthFactor`, `buyoutPrice`, `liquidatorGain`, `liquidatable` | Position RWA (EF-47). `owner` vaut l'adresse nulle si le jeton n'est pas déposé |
| `getBorrowers()` | `address[]` | Adresses qui ont une dette contre tETH. Appeler ensuite `getAccountPosition` sur chacune et garder celles où `liquidatable` est vrai (EF-36) |
| `getRwaTokenIds()` | `uint256[]` | Jetons RWA déposés en garantie. Appeler ensuite `getRwaPosition` sur chacun |
| `previewLiquidation(repayAmount)` | `collateralSeized`, `bonusValue` | Garantie reçue et gain estimé du liquidateur (EF-36) |

Pour le dépôt du prêteur (EF-02), `getAccountPosition` donne trois montants :

- `principal` : les fonds déposés, sans les intérêts. Un retrait le réduit dans la même proportion que le dépôt.
- `interestEarned` : les intérêts générés et pas encore retirés. Il reste à zéro si le dépôt vaut moins que le capital, par exemple après une perte du pool.
- `deposited` : ce que le prêteur peut retirer maintenant. Sans perte, c'est `principal + interestEarned`.

Autres lectures utiles :

- `TestToken.balanceOf(user)` et `TestToken.allowance(user, pool)` : soldes, et approbation à demander seulement si elle est insuffisante (EF-06, EF-08).
- `RWANFT.tokensOf(user)` : jetons RWA détenus par l'utilisateur. `RWANFT.getAsset(tokenId)` : `assetType`, `appraisedValue`, `appraisedAt`, `documentHash`.
- `RWANFT.getApproved(tokenId)` ou `isApprovedForAll(user, pool)` : approbation ERC-721 avant un dépôt de jeton.
- `PriceOracle.priceData(token)` : `price`, `updatedAt`, `valid`.
- `InterestRateModel.borrowRate(u)` et `supplyRate(u)` : taux pour un taux d'utilisation donné.

Deux simulations se font côté interface, sans transaction :

- **Effet d'un dépôt (EF-15).** Nouvelle utilisation = `totalBorrows / (totalLiquidity + montant)`, puis `supplyRate(nouvelle utilisation)` donne le rendement annualisé estimé.
- **Facteur de santé prévu (EF-19).** `collateralValue × 0,8 / (debtValue + valeur du montant saisi)`. Les constantes sont lisibles sur le contrat : `LTV_FUNGIBLE`, `LIQUIDATION_THRESHOLD_FUNGIBLE`, `LTV_RWA`, `LIQUIDATION_THRESHOLD_RWA`.

La dette grossit à chaque seconde. Entre la lecture et la transaction, un emprunt d'exactement `availableToBorrow` peut donc être rejeté : garder une petite marge, ce que demande déjà EF-19.

### Écritures

| Page | Action | Appels, dans l'ordre |
|---|---|---|
| Prêter | Déposer | `tUSDC.approve(pool, montant)` si besoin, puis `pool.deposit(montant)` |
| Prêter | Retirer | `pool.withdraw(montant)` |
| Emprunter | Déposer une garantie | `tETH.approve(pool, montant)` si besoin, puis `pool.depositCollateral(montant)` |
| Emprunter | Emprunter | `pool.borrow(montant)` |
| Emprunter | Rembourser | `tUSDC.approve(pool, montant)` si besoin, puis `pool.repay(montant)` |
| Emprunter | Retirer la garantie | `pool.withdrawCollateral(montant)` |
| Emprunter (RWA) | Déposer le jeton | `rwa.approve(pool, tokenId)`, puis `pool.depositRwa(tokenId)` |
| Emprunter (RWA) | Emprunter | `pool.borrowAgainstRwa(tokenId, montant)` |
| Emprunter (RWA) | Rembourser | `tUSDC.approve(pool, montant)` si besoin, puis `pool.repayRwa(tokenId, montant)` |
| Emprunter (RWA) | Reprendre le jeton | `pool.withdrawRwa(tokenId)`, une fois la dette à zéro |
| Liquider | Liquider une position | `tUSDC.approve(pool, montant)` si besoin, puis `pool.liquidate(emprunteur, montant)` avec `montant ≤ maxLiquidationRepay` |
| Liquider | Racheter une garantie RWA | `tUSDC.approve(pool, buyoutPrice)` si besoin, puis `pool.buyoutRwa(tokenId)` |

Pour « tout retirer » ou « tout rembourser », passer `type(uint256).max` (`ethers.MaxUint256`) à `withdraw`, `repay` ou `repayRwa` : le contrat prend le montant exact au moment de la transaction, intérêts compris. Pour un remboursement total, l'approbation doit couvrir un peu plus que la dette affichée.

Les jetons de test ont une fonction `faucet()` : elle remet 10 000 tUSDC ou 10 tETH à l'appelant.

### Événements

Chaque opération en émet un (EF-05). L'interface peut s'y abonner pour rafraîchir l'affichage.

| Événement de `LendingPool` | Champs |
|---|---|
| `Deposited`, `Withdrawn` | `user` (indexé), `amount`, `shares` |
| `CollateralDeposited`, `CollateralWithdrawn`, `Borrowed`, `Repaid` | `user` (indexé), `amount` |
| `Liquidated` | `liquidator` et `borrower` (indexés), `repaid`, `collateralSeized` |
| `RwaDeposited`, `RwaWithdrawn` | `user` et `tokenId` (indexés) |
| `RwaBorrowed`, `RwaRepaid` | `user` et `tokenId` (indexés), `amount` |
| `RwaBoughtOut` | `liquidator`, `borrower` et `tokenId` (indexés), `price`, `debtRepaid`, `refund`, `shortfall` |
| `InterestAccrued` | `borrowIndex`, `totalBorrows`, `totalReserves` |

Autres contrats : `PriceOracle.PriceUpdated`, `RWANFT.AssetTokenized`, `RWANFT.AppraisalUpdated`.

### Erreurs

Les contrats utilisent des erreurs nommées. Avec ethers v6 et l'ABI du contrat, le nom de l'erreur se lit dans `error.revert.name`.

| Erreur | Signification |
|---|---|
| `ZeroAmount` | Montant nul, ou trop petit pour avoir un effet |
| `InsufficientBalance` | Retrait supérieur au dépôt |
| `InsufficientLiquidity` | Le pool n'a pas assez de fonds disponibles |
| `InsufficientCollateral` | Retrait supérieur à la garantie, ou liquidation qui prendrait plus que la garantie |
| `ExceedsBorrowLimit` | Emprunt au-delà de la limite (75 % ou 50 %) |
| `HealthFactorTooLow` | Le retrait de garantie rendrait la position liquidable |
| `NoDebt` | Rien à rembourser ou à liquider |
| `PositionHealthy` | La position n'est pas liquidable |
| `ExceedsCloseFactor` | Liquidation de plus de 50 % de la dette |
| `NotPositionOwner` | Le jeton RWA n'est pas déposé par l'appelant |
| `DebtOutstanding` | Le jeton RWA ne peut pas être repris tant qu'une dette subsiste |
| `RwaAlreadyDeposited`, `NoRwaPosition` | Jeton déjà déposé, ou pas déposé |
| `PriceNotSet`, `StalePrice` | Prix absent ou périmé dans l'oracle |
| `AppraisalNotSet`, `StaleAppraisal` | Expertise absente ou périmée |

## Chaîne locale

Trois terminaux, ou trois commandes à la suite. La première lance la chaîne et reste ouverte.

```bash
anvil
```

```bash
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

```bash
forge script script/SeedLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --gas-estimate-multiplier 200
```

`Deploy` écrit les adresses dans `deployments/31337.json`. `SeedLocal` crée un état de départ avec les comptes de test d'Anvil :

| Compte Anvil | Rôle | État après `SeedLocal` |
|---|---|---|
| 0 | Administrateur et émetteur RWA | A déployé les contrats |
| 1 | Prêteur | 100 000 tUSDC déposés |
| 2 | Emprunteur | 10 tETH contre 12 000 tUSDC, et une maison expertisée 100 000 $ contre 40 000 tUSDC |
| 3 | Liquidateur | 200 000 tUSDC |

Dans MetaMask : ajouter le réseau `http://127.0.0.1:8545`, identifiant de chaîne `31337`, puis importer les clés de test qu'Anvil affiche au démarrage. Ces clés sont publiques : ne jamais les utiliser ailleurs.

## Scénarios de démonstration

Ce sont les deux scénarios de la proposition (sections 3.2 et 3.3). Ils sont aussi joués par `test/Scenarios.t.sol`, qui raconte chaque étape en français avec les valeurs lues sur les contrats : `forge test --match-contract ScenariosTest -vv`. Les commandes ci-dessous ont été vérifiées sur Anvil, après `SeedLocal`. Remplacer les noms entre chevrons par les adresses de `deployments/<chainId>.json`.

**1. Baisse du prix, puis liquidation.** L'administrateur baisse le prix de tETH de 2 000 $ à 1 400 $. Le facteur de santé de l'emprunteur passe à 0,93 et sa position apparaît dans la page Liquider.

```bash
cast send <PriceOracle> "setPrice(address,uint256)" <tETH> "1400e18" --rpc-url http://127.0.0.1:8545 --unlocked --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

Le liquidateur rembourse ensuite 6 000 tUSDC depuis l'interface et reçoit 4,5 tETH : 6 000 × 1,05 ÷ 1 400.

**2. Nouvelle expertise, puis rachat.** L'émetteur inscrit une expertise plus basse pour la maison : 60 000 $ au lieu de 100 000 $. Le facteur de santé de la position RWA passe à 0,9.

```bash
cast send <RWANFT> "updateAppraisal(uint256,uint256,bytes32)" 1 "60000e18" $(cast keccak "expertise-2") --rpc-url http://127.0.0.1:8545 --unlocked --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

Le liquidateur rachète le jeton pour 57 000 tUSDC depuis l'interface. Le pool récupère les 40 000 de dette, l'emprunteur reçoit les 17 000 restants et le liquidateur reçoit le jeton.

Autres commandes d'administration :

```bash
cast send <RWANFT> "mint(address,string,uint256,bytes32)" <emprunteur> "Montre" "12000e18" $(cast keccak "expertise-montre") --rpc-url http://127.0.0.1:8545 --unlocked --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

```bash
cast send <tUSDC> "mint(address,uint256)" <adresse> "50000e6" --rpc-url http://127.0.0.1:8545 --unlocked --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

Changer les taux (EF-26) se fait en deux commandes. La première arrête les intérêts courus avec les anciens taux : sans elle, les nouveaux taux s'appliqueraient aussi à la période écoulée depuis la dernière opération. Les valeurs sont sur 18 décimales (`3e16` = 3 %, `1e18` = 100 %), dans cet ordre : taux de base, pente avant le point d'inflexion, pente après, point d'inflexion, facteur de réserve.

```bash
cast send <LendingPool> "accrueInterest()" --rpc-url http://127.0.0.1:8545 --unlocked --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

```bash
cast send <InterestRateModel> "setParameters(uint256,uint256,uint256,uint256,uint256)" "3e16" "8e16" "1e18" "8e17" "1e17" --rpc-url http://127.0.0.1:8545 --unlocked --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

Sur Sepolia, remplacer `--rpc-url http://127.0.0.1:8545 --unlocked --from 0xf39F…` par `--rpc-url sepolia --account deployer`.

Avant une démonstration, réinscrire les prix avec `setPrice` : un prix de plus de 30 jours est périmé, et les emprunts et liquidations sont alors rejetés.

## Déploiement sur Sepolia

À faire une fois, par la personne qui tient le compte administrateur. Fait le 22 novembre 2026 : les adresses obtenues sont dans [Adresses sur Sepolia](#adresses-sur-sepolia).

1. Créer le compte de déploiement dans le coffre chiffré de Foundry. La commande demande un mot de passe, puis affiche l'adresse du compte. La clé reste chiffrée sur le poste : elle ne s'affiche jamais et ne doit jamais se retrouver dans un fichier du dépôt.

```bash
cast wallet new deployer
```

2. Vérifier le mot de passe avant d'alimenter le compte : la commande doit afficher la même adresse. Un mot de passe perdu rend le compte inutilisable. Refaire ce test juste avant le déploiement : le mot de passe se tape sans que rien ne s'affiche, et le déploiement ne signale un mot de passe faux qu'après sa simulation, une trentaine de secondes plus tard. Dans ce cas, rien n'est envoyé.

```bash
cast wallet address --account deployer
```

3. Envoyer un peu d'ETH de test à cette adresse. Le [faucet Sepolia de Google](https://cloud.google.com/application/web3/faucet/ethereum/sepolia) en donne 0,05 avec un compte Google ; il peut refuser une adresse qui n'a pas 0,001 ETH sur le réseau principal. Sur Sepolia, créer un contrat coûte bien plus de gaz que sur Anvil : environ 25 millions de gaz pour `LendingPool` et 51 millions pour l'ensemble, 67 avec la marge que prend Foundry. Le 22 novembre 2026, le déploiement a coûté 0,0005 ETH ; si le prix du gaz remonte à 1 gwei, compter 0,07 ETH.

4. Déployer. L'option `--slow` attend la confirmation de chaque transaction avant d'envoyer la suivante. L'alias `sepolia` désigne un nœud public, défini dans `foundry.toml`.

```bash
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --account deployer --sender <adresse du compte> --slow
```

5. Ajouter `deployments/11155111.json` au dépôt : c'est ce que lit l'interface.

Pour utiliser un compte MetaMask existant à la place de l'étape 1 : `cast wallet import deployer --interactive`, qui demande sa clé privée dans le terminal.

Le compte qui déploie devient propriétaire des jetons de test, de l'oracle et du modèle de taux, et émetteur des jetons RWA.

## Test de bout en bout sur Sepolia

`script/EndToEnd.s.sol` rejoue les deux scénarios de démonstration avec de vraies transactions, sur les contrats déployés, avec les montants de la section [Scénarios de démonstration](#scénarios-de-démonstration). Un seul compte joue tous les rôles : prêteur, emprunteur, liquidateur et émetteur RWA. C'est le compte qui a déployé, le seul autorisé à changer les prix et les expertises.

À la fin, le prix du tETH est revenu à 2 000 $ et le compte a retiré tous ses fonds ; le jeton RWA du test lui reste. Le script refuse de démarrer si quelqu'un d'autre a une position d'emprunt : baisser le prix du tETH la rendrait liquidable le temps du test.

Simulation seule, gratuite et sans mot de passe :

```bash
forge script script/EndToEnd.s.sol --rpc-url sepolia --sender <adresse du compte>
```

Pour de vrai, une vingtaine de transactions et quelques minutes :

```bash
forge script script/EndToEnd.s.sol --rpc-url sepolia --broadcast --account deployer --sender <adresse du compte> --slow --gas-estimate-multiplier 200
```

Le 23 novembre 2026, le script a été répété sur Anvil, avec un bloc toutes les 2 secondes pour que les intérêts courent entre les transactions, puis lancé sur Sepolia : 20 transactions réussies, blocs 12 196 772 à 12 196 791, pour 0,000005 ETH. Les événements confirment chaque étape : 4,5 tETH remis au liquidateur, rachat de la maison pour 57 000 tUSDC dont 16 999,998 rendus à l'emprunteur. Les intérêts ont couru entre les transactions : les emprunteurs ont payé 0,002181 tUSDC, dont 0,001965 pour le prêteur et 0,000216 pour la réserve.

Le jeton RWA n° 1 a servi à ce test : il appartient au compte qui a déployé, avec une expertise de 60 000 $. La démonstration utilisera le jeton suivant.

## Tests

| Fichier | Couvre |
|---|---|
| `TestToken.t.sol` | EF-10 |
| `PriceOracle.t.sol` | EF-27 à EF-29, EF-40 |
| `InterestRateModel.t.sol` | EF-22 à EF-24, EF-26 |
| `RWANFT.t.sol` | EF-37, EF-38 |
| `LendingPool.Lender.t.sol` | EF-11 à EF-14, capital et intérêts générés pour EF-02 |
| `LendingPool.Borrow.t.sol` | EF-16 à EF-21, EF-25, EF-29, lectures pour EF-02, EF-03, EF-18 |
| `LendingPool.Liquidation.t.sol` | EF-30 à EF-36, EF-29 (liquidation rejetée sur un prix périmé) |
| `LendingPool.Rwa.t.sol` | EF-39 à EF-47 |
| `LendingPool.Edge.t.sol` | Cas limites : montants infimes, oracle sans prix |
| `Scenarios.t.sol` | Les deux scénarios de démonstration, de bout en bout |

EF-05 (un événement par opération) est vérifié dans chaque fichier `LendingPool.*` avec `vm.expectEmit`.

Couverture mesurée : 100 % des lignes, 99,4 % des instructions, 96,3 % des branches, 100 % des fonctions. Les trois branches non couvertes sont celles d'un pool dont les prêteurs auraient tout perdu.

## Choix de conception

- **Un seul marché.** tUSDC est le seul actif prêté et emprunté, tETH la seule garantie fongible. EF-11 demande de rejeter un dépôt « portant sur un cryptoactif non supporté » : c'est garanti par construction, `deposit` n'accepte aucun autre jeton.
- **Positions RWA isolées.** Chaque jeton déposé porte sa propre dette, séparée de la position tETH du même emprunteur. Les deux types de garantie ont des seuils différents : les mélanger dans un seul facteur de santé aurait compliqué le contrat et l'interface.
- **Une seule source pour l'expertise.** La valeur expertisée est inscrite sur le jeton par l'émetteur, et l'oracle la lit. La proposition parlait d'inscrire la valeur dans l'oracle : la lire sur le jeton évite d'avoir deux valeurs qui peuvent diverger. Le rôle de chacun reste celui des cas d'utilisation : l'émetteur met à jour l'expertise (UC17), l'oracle la fournit au protocole et vérifie qu'elle n'est pas périmée (UC21).
- **Parts pour les prêteurs, dette normalisée pour les emprunteurs.** Les intérêts s'appliquent à tous avec une seule variable, `borrowIndex`, sans parcourir les positions.
- **Capital du prêteur retenu par le pool.** `principalOf` garde ce que chaque prêteur a versé, pour afficher ses intérêts générés (EF-02) sans relire tous les événements. Un retrait partiel reprend capital et intérêts dans la même proportion : retirer la moitié de son dépôt laisse la moitié du capital et la moitié des intérêts.
- **Liquidité suivie en interne.** `totalCash` ne dépend pas du solde réel du contrat : envoyer des jetons directement au pool ne modifie pas la valeur des parts.
- **Arrondis en faveur du pool.** Une dette s'arrondit vers le haut, ce que le pool remet s'arrondit vers le bas.

## Limites connues

- L'oracle est simulé et centralisé : son propriétaire fixe les prix. Un vrai protocole utiliserait un oracle décentralisé.
- Si la garantie fongible ne vaut plus assez pour couvrir la dette et le bonus, la liquidation s'arrête quand la garantie est épuisée et le reste de la dette n'est pas recouvré.
- Le rachat d'une garantie RWA exige du liquidateur le montant complet. Un mécanisme d'enchères serait nécessaire en production, comme le note la proposition.
- La réserve s'accumule dans le pool et sert à absorber les écarts des rachats RWA. Aucune fonction ne permet de la retirer.
- `RWANFT.tokensOf` parcourt tous les jetons émis : suffisant pour une démonstration, pas pour une grande collection.
- Les contrats ne sont ni pausables ni évolutifs, et n'ont pas été audités.

## Dépannage

- **`forge` n'est pas reconnu.** Ajouter le dossier de Foundry au chemin de la session. Sous PowerShell : `$env:Path += ";$HOME\.foundry\bin"`.
- **`forge build` reste bloqué au premier lancement.** Foundry essaie de télécharger le compilateur Solidity 0.8.30 et certains réseaux le bloquent. Le télécharger à la main depuis `binaries.soliditylang.org` et le placer là où Foundry le cherche. Sous Windows : `%APPDATA%\svm\0.8.30\solc-0.8.30`, sans extension.
- **« the previous broadcast has unfinished operations ».** Un envoi précédent a échoué. Relancer la commande avec `--start-fresh`.
- **La chaîne locale est dans un état bizarre.** Arrêter Anvil et le relancer, plutôt que de la remettre à zéro : on repart d'une chaîne vierge et les adresses de déploiement sont les mêmes.
- **Une transaction de `SeedLocal` échoue par manque de gaz.** L'option `--gas-estimate-multiplier 200` a été oubliée. `forge script` estime le gaz en simulant toutes les transactions au même instant, alors que sur la chaîne le pool calcule les intérêts courus entre deux transactions.

## Dépendances

Copiées telles quelles dans `lib/`, parce que le poste de développement n'avait pas Git :

- `forge-std` 1.17.0
- `openzeppelin-contracts` 5.7.0, limité aux dossiers `access`, `interfaces`, `token` et `utils`, moins trois fichiers inutilisés dont le chemin était trop long pour ce poste : `draft-ERC20TemporaryApproval.sol`, `MultiSignerERC7913Weighted.sol` et `ERC7913WebAuthnVerifier.sol`

Avec Git, on peut les remplacer par `forge install foundry-rs/forge-std@v1.17.0` et `forge install OpenZeppelin/openzeppelin-contracts@v5.7.0`. Les chemins d'import ne changent pas.

Compilateur : Solidity 0.8.30, cible EVM `cancun`, fixés dans `foundry.toml`.
