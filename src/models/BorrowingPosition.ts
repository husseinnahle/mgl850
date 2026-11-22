import type { Asset } from "./Asset";
import { formatUnits } from "ethers";

export class BorrowingPosition {
    public readonly collateralAsset: Asset;
    public readonly collateralAmountUnits: bigint;
    public readonly borrowedAsset: Asset;
    public readonly borrowedAmountUnits: bigint;

    constructor(
        collateralAsset: Asset,
        collateralAmountUnits: bigint,
        borrowedAsset: Asset,
        borrowedAmountUnits: bigint,
    ) {
        if (collateralAmountUnits <= 0n || borrowedAmountUnits <= 0n) {
            throw new RangeError("Borrowing position amounts must be greater than zero.");
        }

        this.collateralAsset = collateralAsset;
        this.collateralAmountUnits = collateralAmountUnits;
        this.borrowedAsset = borrowedAsset;
        this.borrowedAmountUnits = borrowedAmountUnits;
    }

    toString(): string {
        const borrowedAmount = formatUnits(
            this.borrowedAmountUnits,
            this.borrowedAsset.decimals,
        );
        const collateralAmount = formatUnits(
            this.collateralAmountUnits,
            this.collateralAsset.decimals,
        );

        return `${borrowedAmount} ${this.borrowedAsset.symbol} empruntés avec ${collateralAmount} ${this.collateralAsset.symbol} en garantie`;
    }
}
