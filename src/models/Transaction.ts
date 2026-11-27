import type { TransactionLabel, TransactionStatus } from "./types";

let nextTransactionId = 0;

export class Transaction {
  public readonly id = `transaction-${++nextTransactionId}`;
  public readonly label: TransactionLabel;
  public readonly userAddress: string;
  private _hash: string | undefined;
  private _status: TransactionStatus;

  constructor(
    hash: string | undefined,
    status: TransactionStatus,
    label: TransactionLabel,
    userAddress: string,
  ) {
    this._hash = hash;
    this._status = status;
    this.label = label;
    this.userAddress = userAddress;
  }

  get hash(): string | undefined {
    return this._hash;
  }

  set hash(newHash: string | undefined) {
    this._hash = newHash;
  }

  get status(): TransactionStatus {
    return this._status;
  }

  set status(newStatus: TransactionStatus) {
    this._status = newStatus;
  }

  formatHash(): string {
    if (this.hash === undefined) {
      return "Pas encore envoyée";
    }
    const prefix = this.hash.slice(0, 7);
    const suffix = this.hash.slice(-5);
    return `${prefix}...${suffix}`;
  }

  toString(): string {
    return `${this.label} - ${this.status}`;
  }
}

export class ChainTransaction extends Transaction {
  public readonly blockNumber: number;
  public readonly logIndex: number;
  public readonly details: string;

  constructor(
    hash: string,
    label: TransactionLabel,
    userAddress: string,
    blockNumber: number,
    logIndex: number,
    details: string,
  ) {
    super(hash, "Confirmée", label, userAddress);
    this.blockNumber = blockNumber;
    this.logIndex = logIndex;
    this.details = details;
  }

  toString(): string {
    return this.details;
  }
}
