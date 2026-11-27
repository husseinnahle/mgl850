import { User } from "../models/User";
import { Portfolio } from "../models/Portfolio";
import { protocolService } from "./ProtocolService";
import { getEthereumProvider } from "../utils/ethereumProvider";

export class WalletService {
  async connect(): Promise<User[]> {
    const provider = getEthereumProvider();
    const accounts: unknown = await provider.send("eth_requestAccounts", []);
    return this.toUsers(accounts);
  }

  async disconnect(): Promise<void> {
    const provider = getEthereumProvider();
    await provider.send("wallet_revokePermissions", [{ eth_accounts: {} }]);
  }

  async getPortfolio(address: string): Promise<Portfolio> {
    return protocolService.getPortfolio(address);
  }

  async getUsers(addresses: string[]): Promise<User[]> {
    return Promise.all(
      addresses.map(
        async (address) => new User(address, await this.getPortfolio(address)),
      ),
    );
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
    return this.getUsers(result);
  }
}
