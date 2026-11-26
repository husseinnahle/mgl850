import { Contract, type ContractTransactionResponse } from "ethers";

import lendingPoolAbi from "../../contracts/abi/LendingPool.json";
import testTokenAbi from "../../contracts/abi/TestToken.json";
import deployments from "../../contracts/deployments/11155111.json";
import type { AccountPosition } from "../models/AccountPosition";
import { getEthereumProvider } from "../utils/ethereumProvider";

export class SepoliaProtocolService {
  private readonly chainId = BigInt(deployments.chainId);
  private readonly chainName = "Sepolia";

  private getTestToken(symbol: "tETH" | "tUSDC"): Contract {
    const address = symbol === "tUSDC" ? deployments.tUSDC : deployments.tETH;
    return new Contract(address, testTokenAbi, getEthereumProvider());
  }

  private async getLendingPool(): Promise<Contract> {
    const provider = getEthereumProvider();
    const signer = await provider.getSigner();
    return new Contract(deployments.LendingPool, lendingPoolAbi, signer);
  }

  async assertSepolia(): Promise<void> {
    const network = await getEthereumProvider().getNetwork();
    if (network.chainId !== this.chainId) {
      throw new Error(`Réseau incorrect. Connectez-vous à ${this.chainName}.`);
    }
  }

  async faucet(symbol: "tETH" | "tUSDC"): Promise<string> {
    await this.assertSepolia();
    const provider = getEthereumProvider();
    const signer = await provider.getSigner();
    const token = this.getTestToken(symbol);
    const tokenWithSigner = token.connect(signer) as Contract;
    const transaction =
      (await tokenWithSigner.faucet()) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  async deposit(amount: bigint): Promise<string> {
    const pool = await this.getLendingPool();
    const transaction = (await pool.deposit(
      amount,
    )) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  async depositCollateral(amount: bigint): Promise<string> {
    const pool = await this.getLendingPool();
    const transaction = (await pool.depositCollateral(
      amount,
    )) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  async borrow(amount: bigint): Promise<string> {
    const pool = await this.getLendingPool();
    const transaction = (await pool.borrow(
      amount,
    )) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  async getAccountPosition(address: string): Promise<AccountPosition> {
    const pool = new Contract(
      deployments.LendingPool,
      lendingPoolAbi,
      getEthereumProvider(),
    );
    const position = await pool.getAccountPosition(address);
    return {
      deposited: position.deposited,
      principal: position.principal,
      interestEarned: position.interestEarned,
      collateral: position.collateral,
      debt: position.debt,
      collateralValue: position.collateralValue,
      debtValue: position.debtValue,
      availableToBorrow: position.availableToBorrow,
      healthFactor: position.healthFactor,
      liquidationPrice: position.liquidationPrice,
      maxLiquidationRepay: position.maxLiquidationRepay,
      liquidatable: position.liquidatable,
    };
  }

}

export const protocolService = new SepoliaProtocolService();
