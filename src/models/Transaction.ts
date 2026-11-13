import type { TransactionLabel, TransactionStatus } from "./types";

export class Transaction {
  public readonly hash: string;
  public readonly label: TransactionLabel;
  public readonly status: TransactionStatus;

  constructor(
    hash: string,
    label: TransactionLabel,
    status: TransactionStatus,
  ) {
    this.hash = hash;
    this.label = label;
    this.status = status;
  }

  formatHash(): string {
    const prefix = this.hash.slice(0, 7);
    const suffix = this.hash.slice(-5);
    return `${prefix}...${suffix}`;
  }
}
