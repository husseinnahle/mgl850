import { useState } from "react";
import { useTimedMessage } from "../hooks/useTimedMessage";
import type { User } from "../models/User";
import { protocolService } from "../services/ProtocolService";

type FaucetPageProps = {
    user: User | undefined;
    onSyncPortfolio: () => Promise<unknown>;
};

export function FaucetPage({
    user,
    onSyncPortfolio,
}: FaucetPageProps) {
    const [isSending, setIsSending] = useState(false);
    const [message, setMessage] = useTimedMessage();

    const requestTokens = async (symbol: "tETH" | "tUSDC") => {
        if (!user || isSending) return;

        setIsSending(true);
        setMessage("");
        try {
            await protocolService.faucet(symbol);
            setMessage(`${symbol} ajouté à votre portefeuille.`);
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
                <h2 className="h5 card-title">Obtenir des jetons de test</h2>

                <div className="d-flex gap-2">
                    <button
                        className="btn btn-outline-primary flex-grow-1"
                        type="button"
                        disabled={!user || isSending}
                        onClick={() => void requestTokens("tUSDC")}
                    >
                        {isSending ? "Transaction en cours..." : "Obtenir tUSDC"}
                    </button>
                    <button
                        className="btn btn-outline-primary flex-grow-1"
                        type="button"
                        disabled={!user || isSending}
                        onClick={() => void requestTokens("tETH")}
                    >
                        {isSending ? "Transaction en cours..." : "Obtenir tETH"}
                    </button>
                </div>

                {message && (
                    <p className="alert alert-info mt-3 mb-0" role="status">
                        {message}
                    </p>
                )}
            </div>
        </section>
    );
}
