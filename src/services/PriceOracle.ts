import type { TokenSymbol } from "../models/Asset";

export interface PriceOracle {
    getPriceInCents(asset: TokenSymbol): bigint;
}

export class SimulatedPriceOracle implements PriceOracle {
    private readonly pricesInCents: Record<TokenSymbol, bigint> = {
        SepoliaETH: 342000n,
        USDC: 100n,
    };

    getPriceInCents(asset: TokenSymbol): bigint {
        return this.pricesInCents[asset];
    }
}

export const priceOracle = new SimulatedPriceOracle();
