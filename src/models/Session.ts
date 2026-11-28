import { User } from "./User";
import type { MarketState } from "./MarketState";
import type { Portfolio } from "./Portfolio";

export class Session {
  public readonly accounts: User[];
  public readonly selectedAddress: string;
  public readonly marketState: MarketState;

  constructor(
    accounts: User[],
    selectedAddress: string,
    marketState: MarketState,
  ) {
    this.accounts = accounts;
    this.selectedAddress = selectedAddress;
    this.marketState = marketState;
  }

  get selectedAccount(): User | undefined {
    return this.accounts.find(
      (account) => account.address === this.selectedAddress,
    );
  }

  withSelectedAddress(address: string): Session {
    return new Session(this.accounts, address, this.marketState);
  }

  withSyncedData(
    address: string,
    portfolio: Portfolio,
    marketState: MarketState,
  ): Session {
    const accounts = this.accounts.map((account) =>
      account.address === address
        ? new User(account.address, portfolio)
        : account,
    );
    return new Session(accounts, this.selectedAddress, marketState);
  }
}
