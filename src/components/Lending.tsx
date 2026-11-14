import { useEffect, useState, type SubmitEvent } from "react";
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

export function Lending({
    user,
    isSyncingPortfolio,
    onSyncPortfolio,
    onTransactionCreated,
}: LendingProps) {
    const [amount, setAmount] = useState("");
    const [message, setMessage] = useState("");
    const [syncedAsset, setSyncedAsset] = useState<Portfolio["assets"][number] | null>(null);
    const [asset, setSelectedAsset] = useState("");
    const userAddress = user?.address;

    useEffect(() => {
        if (!userAddress) return;

        let isCurrent = true;
        void onSyncPortfolio().then((updatedPortfolio) => {
            if (!isCurrent || !updatedPortfolio) return;

            const nativeAsset = updatedPortfolio.findAssetBySymbol("SepoliaETH");
            setSyncedAsset(nativeAsset ?? null);
            setSelectedAsset(nativeAsset?.symbol ?? "");
        });

        return () => {
            isCurrent = false;
        };
    }, [userAddress, onSyncPortfolio]);

    useEffect(() => {
        if (!message) return;

        const timeoutId = window.setTimeout(() => setMessage(""), 3000);
        return () => window.clearTimeout(timeoutId);
    }, [message]);

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
                    <div className="d-flex justify-content-between align-items-center gap-3 mb-3">
                        <div>
                            <span className="form-label d-block mb-1">Solde disponible</span>
                            <span className="text-body-secondary">
                                {!syncedAsset ? "—" : syncedAsset.toString()}
                            </span>
                        </div>
                    </div>

                    <div className="mb-3">
                        <label className="form-label" htmlFor="lending-asset">
                            Actif
                        </label>
                        <select
                            className="form-select"
                            id="lending-asset"
                            value={asset || (!syncedAsset ? "—" : syncedAsset.symbol)}
                        >
                            {syncedAsset ? (
                                <option key={syncedAsset.symbol} value={syncedAsset.symbol}>
                                    {syncedAsset.symbol}
                                </option>
                            ) : (
                                <option value="—">—</option>
                            )}
                        </select>
                    </div>

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
                                onChange={(event) => {
                                    setAmount(event.target.value);
                                    setMessage("");
                                }}
                                required
                            />
                            <span className="input-group-text">{asset}</span>
                        </div>
                        <div className="d-flex gap-2 mt-2" role="group" aria-label="Choisir une fraction du solde">
                            {[25, 50, 75, 100].map((percentage) => (
                                <button
                                    className="btn btn-outline-secondary btn-sm"
                                    key={percentage}
                                    type="button"
                                    onClick={() => applyBalancePercentage(percentage)}
                                >
                                    {percentage === 100 ? "Max" : `${percentage}%`}
                                </button>
                            ))}
                        </div>
                    </div>

                    {!user && (
                        <p className="small text-body-secondary" role="note">
                            Connectez votre portefeuille avant de préparer un dépôt.
                        </p>
                    )}

                    <button
                        className="btn btn-primary w-100"
                        type="submit"
                        disabled={!user}
                    >
                        Soumettre
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