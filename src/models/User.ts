export class User {
  public readonly address: string;

  constructor(address: string) {
    this.address = address;
  }

  formatAddress(): string {
    const prefix = this.address.slice(0, 7);
    const suffix = this.address.slice(-5);
    return `${prefix}...${suffix}`;
  }
}
