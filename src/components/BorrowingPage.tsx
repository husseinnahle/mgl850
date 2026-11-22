import { formatUnits } from "ethers";
import { useState, type SubmitEvent } from "react";
import { BalancePercentageButtons } from "./BalancePercentageButtons";
import { PortfolioAssetField } from "./PortfolioAssetField";
import { useSyncedPortfolioAsset } from "../hooks/useSyncedPortfolioAsset";
import { useTimedMessage } from "../hooks/useTimedMessage";
import { Asset } from "../models/Asset";
import { BorrowingPosition } from "../models/BorrowingPosition";
import type { Portfolio } from "../models/Portfolio";
import { BorrowingTransaction } from "../models/Transaction";
import type { User } from "../models/User";
import { BorrowingCalculator, MAX_CRYPTO_LTV_PERCENT } from "../services/BorrowingCalculator";
import { priceOracle } from "../services/PriceOracle";
import { formatUsdFromCents } from "../utils/formatCurrency";

type BorrowingProps = {
    user: User | undefined;
    isSyncingPortfolio: boolean;
    onSyncPortfolio: () => Promise<Portfolio | null>;
    onTransactionCreated: (transaction: BorrowingTransaction) => void;
};

const borrowedAssetSymbol = "USDC";
const borrowedAssetDecimals = 6;
const borrowedAsset = new Asset(borrowedAssetSymbol, 0n, borrowedAssetDecimals);
const borrowingCalculator = new BorrowingCalculator(priceOracle);

export function BorrowingPage({
    user,
    isSyncingPortfolio,
    onSyncPortfolio,
    onTransactionCreated,
}: BorrowingProps) {
    const [borrowedAmount, setBorrowedAmount] = useState("");
    const [message, setMessage] = useTimedMessage();
    const collateralAsset = useSyncedPortfolioAsset(user?.address, onSyncPortfolio, "SepoliaETH");
    const isFormDisabled = !user || !collateralAsset || isSyncingPortfolio;
    const borrowedAmountUnits = borrowedAsset.parseAmount(borrowedAmount);
    const quote = collateralAsset
        ? borrowingCalculator.quote(borrowedAmountUnits, collateralAsset, borrowedAsset)
        : null;
    const requiredCollateralUnits = quote?.requiredCollateralUnits ?? null;
    const requiredCollateral = requiredCollateralUnits !== null && collateralAsset
        ? formatUnits(requiredCollateralUnits, collateralAsset.decimals)
        : "";
    const maximumBorrowUnits = quote?.maximumBorrowUnits ?? 0n;
    const maximumBorrowAsset = new Asset(
        borrowedAssetSymbol,
        maximumBorrowUnits,
        borrowedAssetDecimals,
    );
    const exceedsMaximumBorrow = quote?.exceedsMaximumBorrow ?? false;

    const handleSubmit = (event: SubmitEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (!user || !collateralAsset || isSyncingPortfolio) return;

        if (borrowedAmountUnits === null) {
            setMessage("Veuillez saisir un montant valide.");
            return;
        }

        if (exceedsMaximumBorrow || requiredCollateralUnits === null) {
            setMessage("Le montant dépasse la limite de 75 % de la garantie.");
            return;
        }

        const position = new BorrowingPosition(
            collateralAsset,
            requiredCollateralUnits,
            borrowedAsset,
            borrowedAmountUnits,
        );
        onTransactionCreated(
            BorrowingTransaction.fromBorrowingPosition(user, position),
        );
        setMessage("Demande d'emprunt préparée.");
    };

    return (
        <section className="card shadow-sm">
            <div className="card-body p-4">
                <h2 className="h5 card-title">Emprunter avec une garantie</h2>

                <form onSubmit={handleSubmit}>
                    <PortfolioAssetField
                        id="borrowing-collateral-asset"
                        label="Actif de garantie"
                        asset={collateralAsset}
                        emptyMessage={user ? "Aucun actif disponible" : "Connectez MetaMask"}
                        disabled={isFormDisabled}
                    />

                    <div className="mb-3">
                        <label className="form-label" htmlFor="borrowing-amount">
                            Montant à emprunter
                        </label>
                        <div className="input-group">
                            <input
                                className="form-control"
                                id="borrowing-amount"
                                type="number"
                                min="0.000001"
                                step="any"
                                placeholder="0,00"
                                value={borrowedAmount}
                                disabled={isFormDisabled}
                                onChange={(event) => {
                                    setBorrowedAmount(event.target.value);
                                    setMessage("");
                                }}
                                required
                            />
                            <span className="input-group-text">{borrowedAssetSymbol}</span>
                        </div>
                        <BalancePercentageButtons
                            asset={maximumBorrowAsset}
                            disabled={isFormDisabled}
                            onSelect={(percentage) => {
                                setBorrowedAmount(
                                    maximumBorrowAsset.atPercentage(percentage).formatBalance(),
                                );
                                setMessage("");
                            }}
                        />
                        <div className="form-text">
                            Emprunt maximal disponible : {quote
                                ? `${formatUnits(quote.maximumBorrowUnits, borrowedAssetDecimals)} ${borrowedAssetSymbol}`
                                : "—"}
                        </div>
                    </div>

                    <div className="mb-4">
                        <label className="form-label" htmlFor="borrowing-collateral-amount">
                            Garantie nécessaire (LTV maximal : {String(MAX_CRYPTO_LTV_PERCENT)}%)
                        </label>
                        <div className="input-group">
                            <input
                                className="form-control"
                                id="borrowing-collateral-amount"
                                type="text"
                                value={requiredCollateral}
                                readOnly
                                disabled={isFormDisabled}
                            />
                            <span className="input-group-text">
                                {collateralAsset?.symbol ?? "ETH"}
                            </span>
                        </div>
                        <div className="form-text">
                            1 {collateralAsset?.symbol ?? "SepoliaETH"} = {formatUsdFromCents(
                                priceOracle.getPriceInCents(collateralAsset?.symbol ?? "SepoliaETH"),
                            )}
                        </div>
                    </div>

                    {exceedsMaximumBorrow && (
                        <p className="alert alert-warning" role="alert">
                            Le montant demandé dépasse la limite de 75 % de votre solde en garantie.
                        </p>
                    )}

                    {!user && (
                        <p className="small text-body-secondary" role="note">
                            Connectez votre portefeuille avant de préparer un emprunt.
                        </p>
                    )}

                    <button
                        className="btn btn-primary w-100"
                        type="submit"
                        disabled={isFormDisabled || exceedsMaximumBorrow}
                    >
                        {isSyncingPortfolio ? "Synchronisation..." : "Soumettre"}
                    </button>

                    {message && (
                        <p className="alert alert-info mt-3 mb-0" role="status">
                            {message}
                        </p>
                    )}
                </form>
            </div>
        </section>
    );
}
