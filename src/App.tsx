import { useState } from 'react'
import { BorrowingPage } from './components/BorrowingPage'
import { FaucetPage } from './components/FaucetPage'
import { LendingPage } from './components/LendingPage'
import { Navigation } from './components/Navigation'
import { pages, type PageId } from './models/pageConfig'
import { TransactionList } from './components/TransactionList'
import { WalletControls } from './components/WalletControls'
import { useWallet } from './hooks/useWallet'

function App() {
  const [currentPage, setCurrentPage] = useState<PageId>('dashboard')
  const wallet = useWallet()
  const activePage = pages.find((page) => page.id === currentPage)
  const selectedAccount = wallet.accounts.find(
    (account) => account.address === wallet.selectedAddress,
  )
  return (
    <div className="min-vh-100 d-flex flex-column">
      <header className="navbar bg-body-tertiary border-bottom sticky-top py-3">
        <div className="container-fluid flex-wrap justify-content-between gap-3">
          <Navigation
            current={currentPage}
            onChange={setCurrentPage}
            isWalletConnected={Boolean(selectedAccount)}
          />
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
        <h1 className="h2 mb-4">{activePage?.label}</h1>
        {wallet.error && (
          <p className="alert alert-danger" role="alert">
            {wallet.error}
          </p>
        )}
        {!selectedAccount ? (
          <section className="card shadow-sm">
            <div className="card-body p-4">
              <p className="mb-0" role="note">
                Connectez MetaMask pour plus d'acces.
              </p>
            </div>
          </section>
        ) : (
          <>
            {currentPage === 'dashboard' && (
              <TransactionList
                transactions={selectedAccount.portfolio.transactions}
              />
            )}
            {currentPage === 'lend' && (
              <LendingPage
                key={wallet.selectedAddress}
                user={selectedAccount}
                isSyncingPortfolio={wallet.isSyncingPortfolio}
                onSyncPortfolio={wallet.syncPortfolio}
              />
            )}
            {currentPage === 'borrow' && (
              <BorrowingPage
                key={wallet.selectedAddress}
                user={selectedAccount}
                isSyncingPortfolio={wallet.isSyncingPortfolio}
                onSyncPortfolio={wallet.syncPortfolio}
              />
            )}
            {currentPage === 'faucet' && (
              <FaucetPage
                user={selectedAccount}
                onSyncPortfolio={wallet.syncPortfolio}
              />
            )}
          </>
        )}
      </main>
    </div>
  )
}

export default App
