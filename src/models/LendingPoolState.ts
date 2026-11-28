export type LendingPoolState = {
  totalLiquidity: bigint;
  availableLiquidity: bigint;
  totalBorrows: bigint;
  totalReserves: bigint;
  utilization: bigint;
  borrowRate: bigint;
  supplyRate: bigint;
  assetPrice: bigint;
  collateralPrice: bigint;
  pricesValid: boolean;
};
