import { useEffect, useState } from "react";
import type { Asset, TokenSymbol } from "../models/Asset";
import type { Portfolio } from "../models/Portfolio";

type SyncedAsset = {
    address: string;
    asset: Asset | null;
};

export function useSyncedPortfolioAsset(
    address: string | undefined,
    onSyncPortfolio: () => Promise<Portfolio | null>,
    symbol: TokenSymbol,
): Asset | null {
    const [syncedAsset, setSyncedAsset] = useState<SyncedAsset | null>(null);

    useEffect(() => {
        if (!address) return;

        let isCurrent = true;
        void onSyncPortfolio().then((portfolio) => {
            if (!isCurrent || !portfolio) return;

            setSyncedAsset({
                address,
                asset: portfolio.findAssetBySymbol(symbol) ?? null,
            });
        });

        return () => {
            isCurrent = false;
        };
    }, [address, onSyncPortfolio, symbol]);

    if (!syncedAsset || syncedAsset.address !== address) return null;
    return syncedAsset.asset;
}
