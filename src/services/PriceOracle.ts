import type { TokenSymbol } from "../models/Asset";
import { Contract } from "ethers";
import priceOracleAbi from "../../contracts/abi/PriceOracle.json";
import deployments from "../../contracts/deployments/11155111.json";
import { getEthereumProvider } from "../utils/ethereumProvider";

export type PriceData = {
    priceInCents: bigint;
    updatedAt: bigint;
    valid: boolean;
};

export interface PriceOracle {
    getPriceData(asset: TokenSymbol): Promise<PriceData>;
    getPriceInCents(asset: TokenSymbol): Promise<bigint>;
}

export class SepoliaPriceOracle implements PriceOracle {
    private getContract(): Contract {
        return new Contract(
            deployments.PriceOracle,
            priceOracleAbi,
            getEthereumProvider(),
        );
    }

    private getTokenAddress(asset: TokenSymbol): string {
        return asset === "tUSDC" ? deployments.tUSDC : deployments.tETH;
    }

    async getPriceData(asset: TokenSymbol): Promise<PriceData> {
        const oracle = this.getContract();
        const [price, updatedAt, valid] = await oracle.priceData(
            this.getTokenAddress(asset),
        );

        return {
            priceInCents: (price as bigint) / 10n ** 16n,
            updatedAt: updatedAt as bigint,
            valid: valid as boolean,
        };
    }

    async getPriceInCents(asset: TokenSymbol): Promise<bigint> {
        const priceData = await this.getPriceData(asset);
        return priceData.valid ? priceData.priceInCents : 0n;
    }
}

export const priceOracle = new SepoliaPriceOracle();
