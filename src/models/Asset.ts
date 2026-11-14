import { formatUnits } from "ethers";

export type AssetSymbol = "SepoliaETH";

export class Asset {
    public readonly symbol: AssetSymbol;
    public readonly balance: bigint;
    public readonly decimals: number;

    constructor(
        symbol: AssetSymbol,
        balance: bigint = 0n,
        decimals: number = 18,
    ) {
        this.symbol = symbol;
        this.balance = balance;
        this.decimals = decimals;
    }

    atPercentage(percentage: number): Asset {
        const newBalance = (this.balance * BigInt(percentage)) / 100n;
        return new Asset(this.symbol, newBalance, this.decimals);
    }

    formatBalance(): string {
        return formatUnits(this.balance, this.decimals);
    }

    toString(): string {
        return `${this.formatBalance()} ${this.symbol}`;
    }
}

