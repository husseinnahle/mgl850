import type { LendingPosition } from "./LendingPosition";
import type { User } from "./User";
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
}

export class LendingTransaction extends Transaction {
  public readonly position: LendingPosition;

  constructor(
    hash: string | undefined,
    status: TransactionStatus,
    position: LendingPosition,
    userAddress: string,
  ) {
    super(hash, status, "Dépôt", userAddress);
    this.position = position;
  }

  static fromLendingPosition(
    user: User,
    position: LendingPosition,
  ): LendingTransaction {
    return new LendingTransaction(
      undefined,
      "Préparée",
      position,
      user.address,
    );
  }

  toString(): string {
    return `${this.formatHash()} | ${this.position.toString()} - ${this.status}`;
  }
}
