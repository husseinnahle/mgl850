import { useState } from 'react'
import { BorrowingPage } from './components/BorrowingPage'
import { LendingPage } from './components/LendingPage'
import { Navigation, type PageId } from './components/Navigation'
import { TransactionList } from './components/TransactionList'
import { WalletControls } from './components/WalletControls'
import { useWallet } from './hooks/useWallet'
import { type Transaction } from './models/Transaction'

const pageContent: Record<PageId, { title: string }> = {
  dashboard: { title: 'Tableau de bord' },
  lend: { title: 'Prêter' },
  borrow: { title: 'Emprunter' },
  liquidate: { title: 'Liquider' },
}

function App() {
  const [currentPage, setCurrentPage] = useState<PageId>('dashboard')
  const [transactions, setTransactions] = useState<Transaction[]>([])
  const wallet = useWallet()
  const activeContent = pageContent[currentPage]
  const selectedAccount = wallet.accounts.find(
    (account) => account.address === wallet.selectedAddress,
  )
  const addTransaction = (transaction: Transaction) => {
    setTransactions((currentTransactions) => [
      transaction,
      ...currentTransactions,
    ])
  }

  return (
    <div className="min-vh-100 d-flex flex-column">
      <header className="navbar bg-body-tertiary border-bottom sticky-top py-3">
        <div className="container-fluid flex-wrap justify-content-between gap-3">
          <Navigation current={currentPage} onChange={setCurrentPage} />
          <WalletControls
            accounts={wallet.accounts}
            selectedAddress={wallet.selectedAddress}
            isConnecting={wallet.isConnecting}
            onSelectAccount={wallet.selectAccount}
            onConnect={wallet.connect}
            onDisconnect={wallet.revokeAccess}
          />
        </div>
      </header>

      <main className="container flex-grow-1 py-5">
        <h1 className="h2 mb-4">{activeContent.title}</h1>
        {wallet.error && (
          <p className="alert alert-danger" role="alert">
            {wallet.error}
          </p>
        )}
        {currentPage === 'dashboard' && (
          <TransactionList
            transactions={transactions.filter(
              (transaction) => transaction.userAddress === wallet.selectedAddress,
            )}
          />
        )}
        {currentPage === 'lend' && (
          <LendingPage
            key={wallet.selectedAddress}
            user={selectedAccount}
            isSyncingPortfolio={wallet.isSyncingPortfolio}
            onSyncPortfolio={wallet.syncPortfolio}
            onTransactionCreated={addTransaction}
          />
        )}
        {currentPage === 'borrow' && (
          <BorrowingPage
            key={wallet.selectedAddress}
            user={selectedAccount}
            isSyncingPortfolio={wallet.isSyncingPortfolio}
            onSyncPortfolio={wallet.syncPortfolio}
            onTransactionCreated={addTransaction}
          />
        )}
      </main>
    </div>
  )
}

export default App
