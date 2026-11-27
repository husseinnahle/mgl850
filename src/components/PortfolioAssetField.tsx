import type { Asset } from "../models/Asset";

type PortfolioAssetFieldProps = {
    label: string;
    asset: Asset | null;
    emptyMessage: string;
    disabled?: boolean;
};

export function PortfolioAssetField({
    label,
    asset,
    emptyMessage,
    disabled = false,
}: PortfolioAssetFieldProps) {
    return (
        <div className="mb-3">
            <label className="form-label">
                {label}
            </label>
            <select
                className="form-select"
                value={asset?.symbol ?? ""}
                disabled={!asset || disabled}
            >
                {asset ? (
                    <option value={asset.symbol}>{asset.symbol}</option>
                ) : (
                    <option value="">{emptyMessage}</option>
                )}
            </select>
            <div className="form-text">
                Solde disponible : {asset?.toString() ?? "—"}
            </div>
        </div>
    );
}
