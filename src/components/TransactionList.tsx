import type { Transaction } from "../models/Transaction";

export function TransactionList({ transactions }: { transactions: Transaction[] }) {
    return (
        <section className="card">
            <h2>Transactions récentes</h2>
            {transactions.length === 0 ? (
                <p>Aucune transaction.</p>
            ) : (
                <ul className="transactions">
                    {transactions.map((transaction) => (
                        <li key={transaction.hash}>
                            <span>
                                {transaction.label}
                                <small className="hash">{transaction.formatHash()}</small>
                            </span>
                            <span>{transaction.status}</span>
                        </li>
                    ))}
                </ul>
            )}
        </section>
    );
}
