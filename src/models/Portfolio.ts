import type { Asset, TokenSymbol } from "./Asset";
import type { LendingPosition } from "./LendingPosition";

export class Portfolio {
  public readonly assets: Asset[];
  public readonly lendingPositions: LendingPosition[];

  constructor(assets: Asset[], lendingPositions: LendingPosition[]) {
    this.assets = assets;
    this.lendingPositions = lendingPositions;
  }

  findAssetBySymbol(symbol: TokenSymbol): Asset | undefined {
    return this.assets.find((asset) => asset.symbol === symbol);
  }
}
