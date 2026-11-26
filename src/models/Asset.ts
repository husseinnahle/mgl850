import { formatUnits, parseUnits } from "ethers";

export type TokenSymbol = "tETH" | "tUSDC";

export class Asset {
    public readonly symbol: TokenSymbol;
    public readonly balance: bigint;
    public readonly decimals: number;

    constructor(
        symbol: TokenSymbol,
        balance: bigint = 0n,
        decimals: number = 18,
    ) {
        this.symbol = symbol;
        this.balance = balance;
        this.decimals = decimals;
    }

    withBalance(balance: bigint): Asset {
        return new Asset(this.symbol, balance, this.decimals);
    }

    atPercentage(percentage: number): Asset {
        const newBalance = (this.balance * BigInt(percentage)) / 100n;
        return this.withBalance(newBalance);
    }

    formatBalance(): string {
        return formatUnits(this.balance, this.decimals);
    }

    parseAmount(value: string): bigint | null {
        if (!value.trim()) return null;

        try {
            const amount = parseUnits(value, this.decimals);
            return amount > 0n ? amount : null;
        } catch {
            return null;
        }
    }

    toString(): string {
        return `${this.formatBalance()} ${this.symbol}`;
    }
}

export const TETH_ASSET = new Asset("tETH", 0n, 18);
export const TUSDC_ASSET = new Asset("tUSDC", 0n, 6);
