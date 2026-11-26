export type AccountPosition = {
    deposited: bigint;
    principal: bigint;
    interestEarned: bigint;
    collateral: bigint;
    debt: bigint;
    collateralValue: bigint;
    debtValue: bigint;
    availableToBorrow: bigint;
    healthFactor: bigint;
    liquidationPrice: bigint;
    maxLiquidationRepay: bigint;
    liquidatable: boolean;
};
