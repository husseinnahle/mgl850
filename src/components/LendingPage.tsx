import { useState, type SubmitEvent } from "react";
import { BalancePercentageButtons } from "./BalancePercentageButtons";
import { PortfolioAssetField } from "./PortfolioAssetField";
import { useSyncedPortfolioAsset } from "../hooks/useSyncedPortfolioAsset";
import { useTimedMessage } from "../hooks/useTimedMessage";
import { LendingPosition } from "../models/LendingPosition";
import type { Portfolio } from "../models/Portfolio";
import { LendingTransaction } from "../models/Transaction";
import type { User } from "../models/User";

type LendingProps = {
    user: User | undefined;
    isSyncingPortfolio: boolean;
    onSyncPortfolio: () => Promise<Portfolio | null>;
    onTransactionCreated: (transaction: LendingTransaction) => void;
};

export function LendingPage({
    user,
    isSyncingPortfolio,
    onSyncPortfolio,
    onTransactionCreated,
}: LendingProps) {
    const [amount, setAmount] = useState("");
    const [message, setMessage] = useTimedMessage();
    const userAddress = user?.address;
    const syncedAsset = useSyncedPortfolioAsset(
        userAddress,
        onSyncPortfolio,
        "SepoliaETH",
    );
    const isFormDisabled = !user || !syncedAsset || isSyncingPortfolio;

    const applyBalancePercentage = (percentage: number) => {
        if (!syncedAsset) return;
        setAmount(syncedAsset.atPercentage(percentage).formatBalance());
        setMessage("");
    };

    const handleSubmit = (event: SubmitEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (!user || !syncedAsset || isSyncingPortfolio) {
            return;
        }
        const position = new LendingPosition(syncedAsset, amount);
        onTransactionCreated(
            LendingTransaction.fromLendingPosition(user, position),
        );
        setMessage(
            "Demande enregistrée.",
        );
    };

    return (
        <section className="card shadow-sm">
            <div className="card-body p-4">
                <h2 className="h5 card-title">Déposer des actifs</h2>

                <form onSubmit={handleSubmit}>
                    <PortfolioAssetField
                        id="lending-asset"
                        label="Actif"
                        asset={syncedAsset}
                        emptyMessage={user ? "Aucun actif disponible" : "Connectez MetaMask"}
                        disabled={isFormDisabled}
                    />

                    <div className="mb-4">
                        <label className="form-label" htmlFor="lending-amount">
                            Montant à prêter
                        </label>
                        <div className="input-group">
                            <input
                                className="form-control"
                                id="lending-amount"
                                type="number"
                                min="0.000000000000000001"
                                step="any"
                                placeholder="0,00"
                                value={amount}
                                disabled={isFormDisabled}
                                onChange={(event) => {
                                    setAmount(event.target.value);
                                    setMessage("");
                                }}
                                required
                            />
                            <span className="input-group-text">{syncedAsset?.symbol ?? "—"}</span>
                        </div>
                        <BalancePercentageButtons
                            asset={syncedAsset}
                            disabled={isFormDisabled}
                            onSelect={applyBalancePercentage}
                        />
                    </div>

                    {!user && (
                        <p className="small text-body-secondary" role="note">
                            Connectez votre portefeuille avant de préparer un dépôt.
                        </p>
                    )}

                    <button
                        className="btn btn-primary w-100"
                        type="submit"
                        disabled={isFormDisabled}
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