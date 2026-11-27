import { formatUnits } from "ethers";
import { useEffect, useState, type SubmitEvent } from "react";
import { BalancePercentageButtons } from "./BalancePercentageButtons";
import { PortfolioAssetField } from "./PortfolioAssetField";
import { useTimedMessage } from "../hooks/useTimedMessage";
import type { AccountPosition } from "../models/AccountPosition";
import { TUSDC_ASSET } from "../models/Asset";
import type { Portfolio } from "../models/Portfolio";
import type { User } from "../models/User";
import {
    BorrowingCalculator,
    MAX_CRYPTO_LTV_PERCENT,
    type BorrowingQuote,
} from "../services/BorrowingCalculator";
import { priceOracle } from "../services/PriceOracle";
import { protocolService } from "../services/ProtocolService";
import { formatUsdFromCents } from "../utils/formatCurrency";

type BorrowingProps = {
    user: User | undefined;
    isSyncingPortfolio: boolean;
    onSyncPortfolio: () => Promise<Portfolio | null>;
};

type BorrowingPreview = BorrowingQuote & {
    collateralPriceInCents: bigint | null;
};

const borrowingCalculator = new BorrowingCalculator(priceOracle);

export function BorrowingPage({
    user,
    isSyncingPortfolio,
    onSyncPortfolio,
}: BorrowingProps) {
    const [borrowedAmount, setBorrowedAmount] = useState("");
    const [message, setMessage] = useTimedMessage();
    const accountPosition: AccountPosition | null = user?.portfolio.accountPosition ?? null;
    const [isSending, setIsSending] = useState(false);
    const [preview, setPreview] = useState<BorrowingPreview | null>(null);
    const collateralAsset = user?.portfolio.findAssetBySymbol("tETH") ?? null;
    const isFormDisabled = !user || !collateralAsset || isSyncingPortfolio || isSending;
    const borrowedAmountUnits = TUSDC_ASSET.parseAmount(borrowedAmount);
    const requiredCollateralUnits = preview?.requiredCollateralUnits ?? null;
    const requiredCollateral = requiredCollateralUnits !== null && collateralAsset
        ? formatUnits(requiredCollateralUnits, collateralAsset.decimals)
        : "";
    const maximumBorrowUnits = preview?.maximumBorrowUnits ?? 0n;
    const maximumBorrowAsset = TUSDC_ASSET.withBalance(maximumBorrowUnits);
    const exceedsMaximumBorrow = preview?.exceedsMaximumBorrow ?? false;

    useEffect(() => {
        if (!collateralAsset) return;

        void Promise.all([
            borrowingCalculator.quote(
                borrowedAmountUnits,
                collateralAsset,
                TUSDC_ASSET,
            ),
            priceOracle.getPriceData(collateralAsset.symbol),
        ]).then(([quote, collateralPrice]) => {
            const maximumBorrowUnits =
                quote.maximumBorrowUnits + (accountPosition?.availableToBorrow ?? 0n);
            setPreview({
                ...quote,
                maximumBorrowUnits,
                exceedsMaximumBorrow:
                    borrowedAmountUnits !== null
                    && borrowedAmountUnits > maximumBorrowUnits,
                collateralPriceInCents: collateralPrice.valid
                    ? collateralPrice.priceInCents
                    : null,
            });
        }).catch(() => {
            setMessage("Impossible de récupérer les informations de prêt.");
        });

    }, [accountPosition?.availableToBorrow, borrowedAmountUnits, collateralAsset, setMessage]);

    const handleSubmit = async (event: SubmitEvent<HTMLFormElement>) => {
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

        setIsSending(true);
        setMessage("");
        try {
            await protocolService.depositCollateral(
                requiredCollateralUnits,
                user.address,
            );
            await protocolService.borrow(borrowedAmountUnits, user.address);
            setMessage("Emprunt confirmé.");
        } catch (error) {
            const reason = error instanceof Error ? error.message : "Erreur inconnue.";
            setMessage(`La transaction a échoué : ${reason}`);
        } finally {
            await onSyncPortfolio();
            setIsSending(false);
        }
    };

    return (
        <section className="card shadow-sm">
            <div className="card-body p-4">
                <h2 className="h5 card-title">Emprunter avec une garantie</h2>

                <form onSubmit={handleSubmit}>
                    <PortfolioAssetField
                        label="Actif de garantie"
                        asset={collateralAsset}
                        emptyMessage="Aucun actif disponible"
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
                            <span className="input-group-text">{TUSDC_ASSET.symbol}</span>
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
                            Emprunt maximal disponible : {accountPosition
                                ? `${formatUnits(accountPosition.availableToBorrow, TUSDC_ASSET.decimals)} ${TUSDC_ASSET.symbol}`
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
                            1 {collateralAsset?.symbol ?? "tETH"} = {preview?.collateralPriceInCents == null
                                ? "Prix indisponible"
                                : formatUsdFromCents(preview.collateralPriceInCents)}
                        </div>
                    </div>

                    {exceedsMaximumBorrow && (
                        <p className="alert alert-warning" role="alert">
                            Le montant demandé dépasse la limite de 75 % de votre solde en garantie.
                        </p>
                    )}

                    <button
                        className="btn btn-primary w-100"
                        type="submit"
                        disabled={isFormDisabled || exceedsMaximumBorrow}
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
