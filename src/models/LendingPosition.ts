import type { Asset } from "./Asset";

export class LendingPosition {
    public readonly asset: Asset;
    public readonly amount: string;

    constructor(asset: Asset, amount: string) {
        this.asset = asset;
        this.amount = amount;
    }
    
    toString(): string {
        return `${this.amount} ${this.asset.symbol}`;
    }
}
