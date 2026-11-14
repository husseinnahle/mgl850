import { useCallback, useEffect, useRef, useState } from "react";

import { User } from "../models/User";
import type { Portfolio } from "../models/Portfolio";
import { WalletService } from "../services/WalletService";

const walletService = new WalletService();

function getErrorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "Une erreur inconnue est survenue pendant la connexion.";
}

export function useWallet() {
  const [accounts, setAccounts] = useState<User[]>([]);
  const [selectedAddress, setSelectedAddress] = useState("");
  const [isConnecting, setIsConnecting] = useState(false);
  const [isSyncingPortfolio, setIsSyncingPortfolio] = useState(false);
  const [error, setError] = useState("");
  const hasActiveSession = useRef(false);

  const requestAccounts = useCallback(
    async (request: () => Promise<User[]>) => {
      setIsConnecting(true);
      setError("");

      try {
        const connectedAccounts = await request();
        hasActiveSession.current = true;
        setAccounts(connectedAccounts);
        setSelectedAddress((currentAddress) =>
          connectedAccounts.some(
            (account) => account.address === currentAddress,
          )
            ? currentAddress
            : (connectedAccounts[0]?.address ?? ""),
        );
      } catch (connectionError) {
        setError(getErrorMessage(connectionError));
      } finally {
        setIsConnecting(false);
      }
    },
    [],
  );

  const connect = useCallback(
    () => requestAccounts(() => walletService.connect()),
    [requestAccounts],
  );

  const syncPortfolio = useCallback(async (): Promise<Portfolio | null> => {
    if (!selectedAddress) {
      setError("Connectez un portefeuille avant de synchroniser le solde.");
      return null;
    }

    setIsSyncingPortfolio(true);
    setError("");

    try {
      const portfolio = await walletService.getPortfolio(selectedAddress);
      setAccounts((currentAccounts) =>
        currentAccounts.map((account) =>
          account.address === selectedAddress
            ? new User(account.address, portfolio)
            : account,
        ),
      );
      return portfolio;
    } catch (syncError) {
      setError(getErrorMessage(syncError));
      return null;
    } finally {
      setIsSyncingPortfolio(false);
    }
  }, [selectedAddress]);

  const revokeAccess = useCallback(async () => {
    setIsConnecting(true);
    setError("");

    try {
      await walletService.disconnect();
      hasActiveSession.current = false;
      setAccounts([]);
      setSelectedAddress("");
    } catch (revokeError) {
      setError(getErrorMessage(revokeError));
    } finally {
      setIsConnecting(false);
    }
  }, []);

  useEffect(() => {
    const provider = window.ethereum;
    if (!provider?.on) return;

    const handleAccountsChanged = (changedAccounts: unknown) => {
      if (
        !Array.isArray(changedAccounts) ||
        !changedAccounts.every(
          (address): address is string => typeof address === "string",
        )
      ) {
        return;
      }

      if (changedAccounts.length === 0) {
        hasActiveSession.current = false;
        setAccounts([]);
        setSelectedAddress("");
        return;
      }

      if (!hasActiveSession.current) return;

      const updatedAccounts = changedAccounts.map(
        (address) => User.fromAddress(address),
      );
      setAccounts(updatedAccounts);
      setSelectedAddress((currentAddress) =>
        changedAccounts.includes(currentAddress)
          ? currentAddress
          : (updatedAccounts[0]?.address ?? ""),
      );
    };

    provider.on("accountsChanged", handleAccountsChanged);
    return () =>
      provider.removeListener?.("accountsChanged", handleAccountsChanged);
  }, []);

  return {
    accounts,
    selectedAddress,
    selectAccount: setSelectedAddress,
    isConnecting,
    isSyncingPortfolio,
    error,
    connect,
    syncPortfolio,
    revokeAccess,
  };
}
