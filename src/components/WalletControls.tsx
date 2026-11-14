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
    <div className="d-flex align-items-center justify-content-end gap-2 flex-wrap">
      {isConnected ? (
        <>
          <select
            className="form-select w-auto"
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
          <button
            className="btn btn-outline-secondary text-nowrap"
            type="button"
            onClick={onDisconnect}
            disabled={isConnecting}
          >
            {isConnecting ? 'Déconnexion en cours...' : 'Se déconnecter'}
          </button>
        </>
      ) : (
        <button
          className="btn btn-primary text-nowrap"
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
