import { formatUnits, parseUnits } from "ethers";

export type TokenSymbol = "SepoliaETH" | "USDC";

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

    atPercentage(percentage: number): Asset {
        const newBalance = (this.balance * BigInt(percentage)) / 100n;
        return new Asset(this.symbol, newBalance, this.decimals);
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

