import type { BorrowerPosition } from "./BorrowerPosition";
import type { LendingPoolState } from "./LendingPoolState";

export type MarketState = {
  pool: LendingPoolState;
  borrowerPositions: BorrowerPosition[];
};
