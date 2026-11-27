import {
  Interface,
  ZeroAddress,
  zeroPadValue,
  type Filter,
  type Log,
} from "ethers";
import lendingPoolAbi from "../../contracts/abi/LendingPool.json";
import testTokenAbi from "../../contracts/abi/TestToken.json";
import deployments from "../../contracts/deployments/11155111.json";
import { TETH_ASSET, TUSDC_ASSET } from "../models/Asset";
import { ChainTransaction } from "../models/Transaction";
import type { TransactionLabel } from "../models/types";
import { getEthereumProvider } from "../utils/ethereumProvider";

export class TransactionHistoryService {
  private readonly lendingPoolInterface = new Interface(lendingPoolAbi);
  private readonly testTokenInterface = new Interface(testTokenAbi);

  async getTransactionHistory(
    address: string,
  ): Promise<ChainTransaction[]> {
    const provider = getEthereumProvider();

    const latestBlock = await provider.getBlockNumber();
    const userTopic = zeroPadValue(address, 32);
    const poolLogs = await this.getPoolLogs(userTopic, latestBlock);
    const [liquidationTransactions, faucetTransactions] = await Promise.all([
      this.getLiquidationTransactions(address, userTopic, latestBlock),
      this.getFaucetTransactions(address, userTopic, latestBlock),
    ]);

    const poolTransactions = poolLogs
      .map((log) => this.createPoolTransaction(log, address))
      .filter(
        (transaction): transaction is ChainTransaction =>
          transaction !== undefined,
      );
    const transactions = [
      ...poolTransactions,
      ...liquidationTransactions,
      ...faucetTransactions,
    ];

    const uniqueTransactions = new Map(
      transactions.map((transaction) => [
        `${transaction.hash}:${transaction.logIndex}`,
        transaction,
      ]),
    );
    return [...uniqueTransactions.values()].sort(
      (left, right) =>
        right.blockNumber - left.blockNumber || right.logIndex - left.logIndex,
    );
  }

  private async getPoolEvents(): Promise<string[]> {
    return [
      "Deposited",
      "Withdrawn",
      "CollateralDeposited",
      "CollateralWithdrawn",
      "Borrowed",
      "Repaid",
    ].map((eventName) => {
      const event = this.lendingPoolInterface.getEvent(eventName);
      if (!event) throw new Error(`Événement ${eventName} absent ou invalide.`);
      return event.topicHash;
    });
  }

  private createPoolTransaction(
    log: Log,
    address: string,
  ): ChainTransaction | undefined {
    const parsed = this.lendingPoolInterface.parseLog(log);
    if (!parsed) return undefined;

    const amount = parsed.args[1] as bigint;
    let label: TransactionLabel;
    let details: string;

    switch (parsed.name) {
      case "Deposited":
        label = "Dépôt";
        details = `${TUSDC_ASSET.withBalance(amount).toString()} déposés`;
        break;
      case "Withdrawn":
        label = "Retrait";
        details = `${TUSDC_ASSET.withBalance(amount).toString()} retirés`;
        break;
      case "CollateralDeposited":
        label = "Garantie";
        details = `${TETH_ASSET.withBalance(amount).toString()} déposés en garantie`;
        break;
      case "CollateralWithdrawn":
        label = "Garantie";
        details = `${TETH_ASSET.withBalance(amount).toString()} retirés de la garantie`;
        break;
      case "Borrowed":
        label = "Emprunt";
        details = `${TUSDC_ASSET.withBalance(amount).toString()} empruntés`;
        break;
      case "Repaid":
        label = "Remboursement";
        details = `${TUSDC_ASSET.withBalance(amount).toString()} remboursés`;
        break;
      default:
        return undefined;
    }

    return new ChainTransaction(
      log.transactionHash,
      label,
      address,
      log.blockNumber,
      log.index,
      details,
    );
  }

  private async getPoolLogs(
    userTopic: string,
    latestBlock: number,
  ): Promise<Log[]> {
    const eventTopics = await this.getPoolEvents();
    return this.getLogsInChunks(
      deployments.LendingPool,
      [eventTopics, userTopic],
      latestBlock,
    );
  }

  private async getLiquidationTransactions(
    address: string,
    userTopic: string,
    latestBlock: number,
  ): Promise<ChainTransaction[]> {
    const liquidatedEvent = this.lendingPoolInterface.getEvent("Liquidated");
    if (!liquidatedEvent) {
      throw new Error("Événement Liquidated absent ou invalide.");
    }

    const [asLiquidator, asBorrower] = await Promise.all([
      this.getLogsInChunks(
        deployments.LendingPool,
        [liquidatedEvent.topicHash, userTopic],
        latestBlock,
      ),
      this.getLogsInChunks(
        deployments.LendingPool,
        [liquidatedEvent.topicHash, null, userTopic],
        latestBlock,
      ),
    ]);

    return [...asLiquidator, ...asBorrower].flatMap((log) => {
      const parsed = this.lendingPoolInterface.parseLog(log);
      if (!parsed) return [];

      return [
        new ChainTransaction(
          log.transactionHash,
          "Liquidation",
          address,
          log.blockNumber,
          log.index,
          `Liquidation de ${parsed.args[1]} : ${TUSDC_ASSET.withBalance(parsed.args[2] as bigint).toString()} remboursés`,
        ),
      ];
    });
  }

  private async getFaucetTransactions(
    address: string,
    userTopic: string,
    latestBlock: number,
  ): Promise<ChainTransaction[]> {
    const transferEvent = this.testTokenInterface.getEvent("Transfer");
    if (!transferEvent) {
      throw new Error("Événement Transfer absent ou invalide.");
    }

    const filter = [
      transferEvent.topicHash,
      zeroPadValue(ZeroAddress, 32),
      userTopic,
    ];
    const [usdcLogs, ethLogs] = await Promise.all([
      this.getLogsInChunks(deployments.tUSDC, filter, latestBlock),
      this.getLogsInChunks(deployments.tETH, filter, latestBlock),
    ]);

    return [
      ...usdcLogs.map((log) => ({ log, asset: TUSDC_ASSET })),
      ...ethLogs.map((log) => ({ log, asset: TETH_ASSET })),
    ].flatMap(({ log, asset }) => {
      const parsed = this.testTokenInterface.parseLog(log);
      if (!parsed) return [];

      return [
        new ChainTransaction(
          log.transactionHash,
          "Faucet",
          address,
          log.blockNumber,
          log.index,
          `Faucet : ${asset.withBalance(parsed.args[2] as bigint).toString()}`,
        ),
      ];
    });
  }

  private async getLogsInChunks(
    address: string,
    topics: Filter["topics"],
    latestBlock: number,
  ): Promise<Log[]> {
    const provider = getEthereumProvider();
    const logs: Log[] = [];
    const firstBlock = deployments.deployBlock;
    const maxRange = 9_000;
    for (
      let fromBlock = firstBlock;
      fromBlock <= latestBlock;
      fromBlock += maxRange
    ) {
      const toBlock = Math.min(fromBlock + maxRange - 1, latestBlock);
      const filter = { address, fromBlock, toBlock, topics };
      const chunkLogs = await provider.getLogs(filter);
      logs.push(...chunkLogs);
    }
    return logs;
  }
}

export const transactionHistoryService = new TransactionHistoryService();
