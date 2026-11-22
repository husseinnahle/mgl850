import type { TokenSymbol } from "../models/Asset";

export const chainId = 11155111n;
export const chainName = "Sepolia";

export interface ProtocolService {
    deposit(userAddress: string, asset: TokenSymbol, amount: string): Promise<void>;
    withdraw(userAddress: string, amount: bigint): Promise<void>;
    borrow(userAddress: string, asset: TokenSymbol, amount: string): Promise<void>;
    repay(userAddress: string, asset: TokenSymbol, amount: string): Promise<void>;
    liquidate(userAddress: string): Promise<void>;
    getPriceInCents(asset: TokenSymbol): bigint;
}
