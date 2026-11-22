import type { LendingPosition } from "./LendingPosition";
import type { BorrowingPosition } from "./BorrowingPosition";
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

  toString(): string {
    return `${this.label} - ${this.status}`;
  }
}

export abstract class PositionTransaction<TPosition extends LendingPosition | BorrowingPosition> extends Transaction {
  public readonly position: TPosition;

  constructor(
    hash: string | undefined,
    status: TransactionStatus,
    label: TransactionLabel,
    position: TPosition,
    userAddress: string,
  ) {
    super(hash, status, label, userAddress);
    this.position = position;
  }

  toString(): string {
    return this.position.toString();
  }
}

export class LendingTransaction extends PositionTransaction<LendingPosition> {
  constructor(
    hash: string | undefined,
    status: TransactionStatus,
    position: LendingPosition,
    userAddress: string,
  ) {
    super(hash, status, "Dépôt", position, userAddress);
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
}

export class BorrowingTransaction extends PositionTransaction<BorrowingPosition> {
  constructor(
    hash: string | undefined,
    status: TransactionStatus,
    position: BorrowingPosition,
    userAddress: string,
  ) {
    super(hash, status, "Emprunt", position, userAddress);
  }

  static fromBorrowingPosition(
    user: User,
    position: BorrowingPosition,
  ): BorrowingTransaction {
    return new BorrowingTransaction(
      undefined,
      "Préparée",
      position,
      user.address,
    );
  }
}
