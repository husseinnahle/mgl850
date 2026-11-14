import { BrowserProvider } from "ethers";
import { User } from "../models/User";
import { Portfolio } from "../models/Portfolio";
import { chainId, chainName } from "./ProtocolService";
import { Asset } from "../models/Asset";

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
    const accounts: unknown = await provider.send("eth_requestAccounts", []);
    return this.toUsers(accounts);
  }

  async disconnect(): Promise<void> {
    const provider = this.getProvider();
    await provider.send("wallet_revokePermissions", [{ eth_accounts: {} }]);
  }

  async getPortfolio(address: string): Promise<Portfolio> {
    const provider = this.getProvider();
    const network = await provider.getNetwork();
    if (network.chainId !== chainId) {
      throw new Error(
        `Réseau MetaMask incorrect. Connectez-vous à ${chainName} et réessayez.`,
      );
    }
    const balance = await provider.getBalance(address);
    return new Portfolio([new Asset("SepoliaETH", balance, 18)], []);
  }

  private async toUsers(result: unknown): Promise<User[]> {
    if (
      !Array.isArray(result) ||
      !result.every((address): address is string => typeof address === "string")
    ) {
      throw new Error("MetaMask a renvoyé une liste de comptes invalide.");
    }
    if (result.length === 0) {
      throw new Error("Aucun compte MetaMask trouvé.");
    }
    return Promise.all(
      result.map(
        async (address) => new User(address, await this.getPortfolio(address)),
      ),
    );
  }
}
