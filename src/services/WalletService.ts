import { BrowserProvider } from "ethers";
import { User } from "../models/User";

export class WalletService {
  getProvider(): BrowserProvider {
    if (!window.ethereum) {
      throw new Error(
        "MetaMask est introuvable. Installez ou activez l'extension.",
      );
    }
    return new BrowserProvider(window.ethereum);
  }

  async connect(): Promise<User[]> {
    const provider = this.getProvider();
    const accounts: any = await provider.send("eth_requestAccounts", []);
    return this.toUsers(accounts);
  }

  async disconnect(): Promise<void> {
    const provider = this.getProvider();
    await provider.send("wallet_revokePermissions", [{ eth_accounts: {} }]);
  }

  private toUsers(result: any): User[] {
    if (
      !Array.isArray(result) ||
      !result.every((address): address is string => typeof address === "string")
    ) {
      throw new Error("MetaMask a renvoyé une liste de comptes invalide.");
    }

    const accounts = result;
    if (accounts.length === 0) {
      throw new Error("Aucun compte MetaMask trouvé.");
    }

    return accounts.map((address) => new User(address));
  }
}
