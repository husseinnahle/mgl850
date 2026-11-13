import { useState } from 'react'
import { Navigation, type PageId } from './components/Navigation'
import { TransactionList } from './components/TransactionList'
import { WalletControls } from './components/WalletControls'
import { useWallet } from './hooks/useWallet'
import './App.css'

const pageContent: Record<PageId, { title: string }> = {
  dashboard: { title: 'Tableau de bord' },
  lend: { title: 'Prêter' },
  borrow: { title: 'Emprunter' },
  liquidate: { title: 'Liquider' },
}

function App() {
  const [currentPage, setCurrentPage] = useState<PageId>('dashboard')
  const wallet = useWallet()
  const activeContent = pageContent[currentPage]

  return (
    <div className="app-shell">
      <header className="app-header">
        <Navigation current={currentPage} onChange={setCurrentPage} />
        <WalletControls
          accounts={wallet.accounts}
          selectedAddress={wallet.selectedAddress}
          isConnecting={wallet.isConnecting}
          onSelectAccount={wallet.selectAccount}
          onConnect={wallet.connect}
          onDisconnect={wallet.revokeAccess}
        />
      </header>

      <main className="page-content">
        <h1>{activeContent.title}</h1>
        {wallet.error && (
          <p className="wallet-error" role="alert">
            {wallet.error}
          </p>
        )}
        {currentPage === 'dashboard' && <TransactionList transactions={[]} />}
      </main>
    </div>
  )
}

export default App
