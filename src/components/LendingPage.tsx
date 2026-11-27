import { useState, type SubmitEvent } from "react";
import { BalancePercentageButtons } from "./BalancePercentageButtons";
import { PortfolioAssetField } from "./PortfolioAssetField";
import { useTimedMessage } from "../hooks/useTimedMessage";
import type { Portfolio } from "../models/Portfolio";
import type { User } from "../models/User";
import { protocolService } from "../services/ProtocolService";

type LendingProps = {
    user: User | undefined;
    isSyncingPortfolio: boolean;
    onSyncPortfolio: () => Promise<Portfolio | null>;
};

export function LendingPage({
    user,
    isSyncingPortfolio,
    onSyncPortfolio,
}: LendingProps) {
    const [amount, setAmount] = useState("");
    const [isSending, setIsSending] = useState(false);
    const [message, setMessage] = useTimedMessage();
    const syncedAsset = user?.portfolio.findAssetBySymbol("tUSDC") ?? null;
    const isFormDisabled = !user || !syncedAsset || isSyncingPortfolio;

    const applyBalancePercentage = (percentage: number) => {
        if (!syncedAsset) return;
        setAmount(syncedAsset.atPercentage(percentage).formatBalance());
        setMessage("");
    };

    const handleSubmit = async (event: SubmitEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (!user || !syncedAsset || isSyncingPortfolio) {
            return;
        }
        const amountUnits = syncedAsset.parseAmount(amount);
        if (amountUnits === null) {
            setMessage("Montant invalide.");
            return;
        }

        setIsSending(true);
        setMessage("");
        try {
            await protocolService.deposit(amountUnits, user.address);
            setMessage("Dépôt confirmé.");
            await onSyncPortfolio();
        } catch (error) {
            setMessage("La transaction a échoué.");
        } finally {
            setIsSending(false);
        }
    };

    return (
        <section className="card shadow-sm">
            <div className="card-body p-4">
                <h2 className="h5 card-title">Déposer des actifs</h2>

                <form onSubmit={handleSubmit}>
                    <PortfolioAssetField
                        label="Actif"
                        asset={syncedAsset}
                        emptyMessage="Aucun actif disponible"
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
                            disabled={isFormDisabled || isSending}
                            onSelect={applyBalancePercentage}
                        />
                    </div>

                    <button
                        className="btn btn-primary w-100"
                        type="submit"
                        disabled={isFormDisabled || isSending}
                    >
                        {isSending ? "Transaction en cours..." : isSyncingPortfolio ? "Synchronisation..." : "Soumettre"}
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
