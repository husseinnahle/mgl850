import { Portfolio } from "./Portfolio";

export class User {
  public readonly address: string;
  public readonly portfolio: Portfolio;

  constructor(address: string, portfolio: Portfolio) {
    this.address = address;
    this.portfolio = portfolio;
  }

  formatAddress(): string {
    const prefix = this.address.slice(0, 7);
    const suffix = this.address.slice(-5);
    return `${prefix}...${suffix}`;
  }

}
