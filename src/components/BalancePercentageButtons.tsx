import type { Asset } from "../models/Asset";

export function BalancePercentageButtons({
    asset,
    onSelect,
    disabled = false,
}: {
    asset: Asset | null;
    onSelect: (percentage: number) => void;
    disabled?: boolean;
}) {
    return (
        <div className="d-flex gap-2 mt-2" role="group" aria-label="Choisir une fraction du solde">
            {[25, 50, 75, 100].map((percentage) => (
                <button
                    className="btn btn-outline-secondary btn-sm"
                    key={percentage}
                    type="button"
                    onClick={() => onSelect(percentage)}
                    disabled={!asset || disabled}
                >
                    {percentage === 100 ? "Max" : `${percentage}%`}
                </button>
            ))}
        </div>
    );
}
