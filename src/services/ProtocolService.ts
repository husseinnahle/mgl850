import {
  Contract,
  type ContractTransactionResponse,
} from "ethers";
import lendingPoolAbi from "../../contracts/abi/LendingPool.json";
import testTokenAbi from "../../contracts/abi/TestToken.json";
import deployments from "../../contracts/deployments/11155111.json";
import type { AccountPosition } from "../models/AccountPosition";
import { TETH_ASSET, TUSDC_ASSET } from "../models/Asset";
import type { BorrowerPosition } from "../models/BorrowerPosition";
import type { LendingPoolState } from "../models/LendingPoolState";
import type { MarketState } from "../models/MarketState";
import { Portfolio } from "../models/Portfolio";
import { getEthereumProvider } from "../utils/ethereumProvider";
import { transactionHistoryService } from "./TransactionHistoryService";

export class SepoliaProtocolService {
  private readonly chainId = BigInt(deployments.chainId);
  private readonly chainName = "Sepolia";

  private getTestToken(symbol: "tETH" | "tUSDC"): Contract {
    const address = symbol === "tUSDC" ? deployments.tUSDC : deployments.tETH;
    return new Contract(address, testTokenAbi, getEthereumProvider());
  }

  private async getLendingPool(address: string): Promise<Contract> {
    const provider = getEthereumProvider();
    const signer = await provider.getSigner(address);
    return new Contract(deployments.LendingPool, lendingPoolAbi, signer);
  }

  async assertSepolia(): Promise<void> {
    const network = await getEthereumProvider().getNetwork();
    if (network.chainId !== this.chainId) {
      throw new Error(`Réseau incorrect. Connectez-vous à ${this.chainName}.`);
    }
  }

  async getPortfolio(address: string): Promise<Portfolio> {
    await this.assertSepolia();
    const [tEthBalance, usdcBalance, accountPosition, transactions] =
      await Promise.all([
      this.getTestToken("tETH").balanceOf(address),
      this.getTestToken("tUSDC").balanceOf(address),
      this.getAccountPosition(address),
      transactionHistoryService.getTransactionHistory(address),
    ]);

    return new Portfolio(
      [
        TETH_ASSET.withBalance(tEthBalance as bigint),
        TUSDC_ASSET.withBalance(usdcBalance as bigint),
      ],
      accountPosition,
      transactions,
    );
  }

  async getMarketState(): Promise<MarketState> {
    const [pool, borrowerPositions] = await Promise.all([
      this.getPoolState(),
      this.getBorrowerPositions(),
    ]);
    return { pool, borrowerPositions };
  }

  async faucet(symbol: "tETH" | "tUSDC", address: string): Promise<string> {
    await this.assertSepolia();
    const provider = getEthereumProvider();
    const signer = await provider.getSigner(address);
    const token = this.getTestToken(symbol);
    const tokenWithSigner = token.connect(signer) as Contract;
    const transaction =
      (await tokenWithSigner.faucet()) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  async deposit(amount: bigint, address: string): Promise<string> {
    await this.approveIfNeeded("tUSDC", amount, address);
    const pool = await this.getLendingPool(address);
    const transaction = (await pool.deposit(
      amount,
    )) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  async depositCollateral(amount: bigint, address: string): Promise<string> {
    await this.approveIfNeeded("tETH", amount, address);
    const pool = await this.getLendingPool(address);
    const transaction = (await pool.depositCollateral(
      amount,
    )) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  async borrow(amount: bigint, address: string): Promise<string> {
    const pool = await this.getLendingPool(address);
    const transaction = (await pool.borrow(
      amount,
    )) as ContractTransactionResponse;
    await transaction.wait();
    return transaction.hash;
  }

  private async approveIfNeeded(
    symbol: "tETH" | "tUSDC",
    amount: bigint,
    address: string,
  ): Promise<void> {
    await this.assertSepolia();
    const signer = await getEthereumProvider().getSigner(address);
    const token = this.getTestToken(symbol);
    const allowance = (await token.allowance(
      address,
      deployments.LendingPool,
    )) as bigint;

    if (allowance >= amount) return;

    const approval = (await (token.connect(signer) as Contract).approve(
      deployments.LendingPool,
      amount,
    )) as ContractTransactionResponse;
    await approval.wait();
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

  private async getPoolState(): Promise<LendingPoolState> {
    const pool = new Contract(
      deployments.LendingPool,
      lendingPoolAbi,
      getEthereumProvider(),
    );
    const state = await pool.getPoolState();
    return {
      totalLiquidity: state.totalLiquidity as bigint,
      availableLiquidity: state.availableLiquidity as bigint,
      totalBorrows: state.totalBorrows as bigint,
      totalReserves: state.totalReserves as bigint,
      utilization: state.utilization as bigint,
      borrowRate: state.borrowRate as bigint,
      supplyRate: state.supplyRate as bigint,
      assetPrice: state.assetPrice as bigint,
      collateralPrice: state.collateralPrice as bigint,
      pricesValid: state.pricesValid as boolean,
    };
  }

  private async getBorrowerPositions(): Promise<BorrowerPosition[]> {
    const pool = new Contract(
      deployments.LendingPool,
      lendingPoolAbi,
      getEthereumProvider(),
    );
    const addresses = (await pool.getBorrowers()) as string[];
    return Promise.all(
      addresses.map(async (address) => ({
        address,
        position: await this.getAccountPosition(address),
      })),
    );
  }

}

export const protocolService = new SepoliaProtocolService();
