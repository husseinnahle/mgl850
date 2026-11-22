import type { Transaction } from "../models/Transaction";

export function TransactionList({ transactions }: { transactions: Transaction[] }) {
    return (
        <section className="card shadow-sm mt-4">
            <div className="card-body">
                <h2 className="h5 card-title">Transactions récentes</h2>
                {transactions.length === 0 ? (
                    <p className="mb-0">Aucune transaction.</p>
                ) : (
                    <ul className="list-group list-group-flush">
                        {transactions.map((transaction) => (
                            <li
                                key={transaction.id}
                                className="list-group-item d-flex justify-content-between align-items-center gap-3 px-0"
                            >
                                <span>
                                    {transaction.label}
                                    <small className="d-block text-body-secondary">
                                        {transaction.toString()}
                                    </small>
                                    <small className="d-block text-body-secondary">
                                        {transaction.formatHash()}
                                    </small>
                                </span>
                                <span>{transaction.status}</span>
                            </li>
                        ))}
                    </ul>
                )}
            </div>
        </section>
    );
}
