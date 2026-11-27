import type { Asset } from "../models/Asset";
import type { PriceOracle } from "./PriceOracle";

export const MAX_CRYPTO_LTV_PERCENT = 75n;

export type BorrowingQuote = {
    maximumBorrowUnits: bigint; // Le montant maximum pouvant être emprunté
    requiredCollateralUnits: bigint | null; // Le montant de garantie requis pour le montant emprunté spécifié, ou null si le montant emprunté est null
    exceedsMaximumBorrow: boolean; // Indique si le montant emprunté dépasse le maximum autorisé
};

export class BorrowingCalculator {
    private readonly priceOracle: PriceOracle;

    constructor(priceOracle: PriceOracle) {
        this.priceOracle = priceOracle;
    }

    async quote(
        borrowedAmountUnits: bigint | null,
        collateralAsset: Asset,
        borrowedAsset: Asset,
    ): Promise<BorrowingQuote> {
        const maximumBorrowUnits = await this.maximumBorrowUnits(
            collateralAsset.balance,
            collateralAsset,
            borrowedAsset,
        );
        const requiredCollateralUnits = borrowedAmountUnits === null
            ? null
            : await this.requiredCollateralUnits(
                borrowedAmountUnits,
                borrowedAsset,
                collateralAsset,
            );

        return {
            maximumBorrowUnits,
            requiredCollateralUnits,
            exceedsMaximumBorrow: borrowedAmountUnits !== null
                && borrowedAmountUnits > maximumBorrowUnits,
        };
    }

    async requiredCollateralUnits(
        borrowedAmountUnits: bigint,
        borrowedAsset: Asset,
        collateralAsset: Asset,
    ): Promise<bigint> {
        const [borrowedPrice, collateralPrice] = await Promise.all([
            this.priceOracle.getPriceInCents(borrowedAsset.symbol),
            this.priceOracle.getPriceInCents(collateralAsset.symbol),
        ]);
        const numerator =
            borrowedAmountUnits *
            borrowedPrice *
            100n *
            tokenUnit(collateralAsset);
        const denominator =
            tokenUnit(borrowedAsset) *
            collateralPrice *
            MAX_CRYPTO_LTV_PERCENT;

        return divideCeiling(numerator, denominator);
    }

    async maximumBorrowUnits(
        collateralAmountUnits: bigint,
        collateralAsset: Asset,
        borrowedAsset: Asset,
    ): Promise<bigint> {
        const [collateralPrice, borrowedPrice] = await Promise.all([
            this.priceOracle.getPriceInCents(collateralAsset.symbol),
            this.priceOracle.getPriceInCents(borrowedAsset.symbol),
        ]);
        const numerator =
            collateralAmountUnits *
            collateralPrice *
            MAX_CRYPTO_LTV_PERCENT *
            tokenUnit(borrowedAsset);
        const denominator =
            tokenUnit(collateralAsset) *
            borrowedPrice *
            100n;

        return numerator / denominator;
    }
}

function tokenUnit(asset: Asset): bigint {
    return 10n ** BigInt(asset.decimals);
}

function divideCeiling(numerator: bigint, denominator: bigint): bigint {
    if (denominator <= 0n) {
        throw new RangeError("Price and LTV must be greater than zero.");
    }
    return (numerator + denominator - 1n) / denominator;
}
