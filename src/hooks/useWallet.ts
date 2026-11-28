import { useCallback, useEffect, useRef, useState } from "react";

import { Session } from "../models/Session";
import { WalletService } from "../services/WalletService";

const walletService = new WalletService();

function getErrorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "Une erreur inconnue est survenue pendant la connexion.";
}

export function useWallet() {
  const [session, setSession] = useState<Session | null>(null);
  const selectedAddress = session?.selectedAddress;
  const [isConnecting, setIsConnecting] = useState(false);
  const [isSyncingSession, setIsSyncingSession] = useState(false);
  const [error, setError] = useState("");
  const hasActiveSession = useRef(false);
  const accountChangeRequest = useRef(0);
  const activeSessionSyncs = useRef(0);
  const sessionSyncRequests = useRef(new Map<string, number>());
  const nextSessionSyncRequest = useRef(0);

  const syncSessionForAddress = useCallback(async (
    address: string,
  ): Promise<void> => {
    if (!address) return;

    const requestId = ++nextSessionSyncRequest.current;
    sessionSyncRequests.current.set(address, requestId);
    activeSessionSyncs.current += 1;
    setIsSyncingSession(true);
    setError("");

    try {
      const [portfolio, marketState] = await Promise.all([
        walletService.getPortfolio(address),
        walletService.getMarketState(),
      ]);
      if (
        sessionSyncRequests.current.get(address) === requestId &&
        hasActiveSession.current
      ) {
        setSession((currentSession) =>
          currentSession?.withSyncedData(address, portfolio, marketState) ??
          currentSession,
        );
      }
    } catch (syncError) {
      if (sessionSyncRequests.current.get(address) === requestId) {
        setError(getErrorMessage(syncError));
      }
    } finally {
      activeSessionSyncs.current -= 1;
      setIsSyncingSession(activeSessionSyncs.current > 0);
    }
  }, []);

  const connect = useCallback(async () => {
    setIsConnecting(true);
    setError("");

    try {
      const accounts = await walletService.connect();
      const marketState = await walletService.getMarketState();
      hasActiveSession.current = true;
      setSession((currentSession) => {
        const selectedAddress =
          currentSession &&
          accounts.some(
            (account) => account.address === currentSession.selectedAddress,
          )
            ? currentSession.selectedAddress
            : (accounts[0]?.address ?? "");
        return new Session(accounts, selectedAddress, marketState);
      });
    } catch (connectionError) {
      setError(getErrorMessage(connectionError));
    } finally {
      setIsConnecting(false);
    }
  }, []);

  const syncSession = useCallback((): Promise<void> => {
    if (!selectedAddress) return Promise.resolve();
    return syncSessionForAddress(selectedAddress);
  }, [selectedAddress, syncSessionForAddress]);

  const selectAccount = useCallback((address: string) => {
    setSession((currentSession) =>
      currentSession?.withSelectedAddress(address) ?? currentSession,
    );
    if (address) void syncSessionForAddress(address);
  }, [syncSessionForAddress]);

  const revokeAccess = useCallback(async () => {
    setIsConnecting(true);
    setError("");

    try {
      await walletService.disconnect();
      hasActiveSession.current = false;
      sessionSyncRequests.current.clear();
      setSession(null);
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

      const requestId = ++accountChangeRequest.current;
      if (changedAccounts.length === 0) {
        hasActiveSession.current = false;
        sessionSyncRequests.current.clear();
        setSession(null);
        return;
      }

      if (!hasActiveSession.current) return;

      setError("");
      sessionSyncRequests.current.clear();
      void Promise.all([
        walletService.getUsers(changedAccounts),
        walletService.getMarketState(),
      ]).then(([updatedAccounts, marketState]) => {
        if (
          requestId !== accountChangeRequest.current ||
          !hasActiveSession.current
        ) {
          return;
        }
        setSession((currentSession) => {
          const selectedAddress =
            currentSession &&
            changedAccounts.includes(currentSession.selectedAddress)
              ? currentSession.selectedAddress
              : (updatedAccounts[0]?.address ?? "");
          return new Session(updatedAccounts, selectedAddress, marketState);
        });
      }).catch((accountError: unknown) => {
        if (requestId !== accountChangeRequest.current) return;
        setError(getErrorMessage(accountError));
        setSession(null);
      });
    };

    provider.on("accountsChanged", handleAccountsChanged);
    return () =>
      provider.removeListener?.("accountsChanged", handleAccountsChanged);
  }, []);

  return {
    session,
    selectAccount,
    isConnecting,
    isSyncingSession,
    error,
    connect,
    syncSession,
    revokeAccess,
  };
}
