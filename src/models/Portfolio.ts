import type { Asset, TokenSymbol } from "./Asset";
import type { AccountPosition } from "./AccountPosition";
import type { Transaction } from "./Transaction";

export class Portfolio {
  public readonly assets: Asset[];
  public readonly accountPosition: AccountPosition | null;
  public readonly transactions: Transaction[];

  constructor(
    assets: Asset[],
    accountPosition: AccountPosition | null,
    transactions: Transaction[],
  ) {
    this.assets = assets;
    this.accountPosition = accountPosition;
    this.transactions = transactions;
  }

  findAssetBySymbol(symbol: TokenSymbol): Asset | undefined {
    return this.assets.find((asset) => asset.symbol === symbol);
  }
}
