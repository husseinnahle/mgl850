import type { User } from "../models/User";

type WalletControlsProps = {
  accounts: User[];
  selectedAddress: string;
  isConnecting: boolean;
  onSelectAccount: (address: string) => void;
  onConnect: () => Promise<void>;
  onDisconnect: () => Promise<void>;
};

export function WalletControls({
  accounts,
  selectedAddress,
  isConnecting,
  onSelectAccount,
  onConnect,
  onDisconnect,
}: WalletControlsProps) {
  const isConnected = accounts.length > 0;

  return (
    <div className="wallet-controls">
      {isConnected ? (
        <>
          <label className="account-selector">
            <select
              aria-label="Compte actif"
              value={selectedAddress}
              onChange={(event) => onSelectAccount(event.target.value)}
            >
              {accounts.map((account) => (
                <option key={account.address} value={account.address}>
                  {account.formatAddress()}
                </option>
              ))}
            </select>
          </label>
          <div className="wallet-actions">
            <button
              className="wallet-button wallet-button--secondary"
              type="button"
              onClick={onDisconnect}
              disabled={isConnecting}
            >
              {isConnecting ? 'Déconnexion en cours...' : 'Se déconnecter'}
            </button>
          </div>
        </>
      ) : (
        <button
          className="wallet-button"
          type="button"
          onClick={onConnect}
          disabled={isConnecting}
        >
          {isConnecting ? 'Connexion en cours...' : 'Connecter MetaMask'}
        </button>
      )}
    </div>
  );
}
