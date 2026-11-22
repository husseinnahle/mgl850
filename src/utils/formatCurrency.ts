export function formatUsdFromCents(priceInCents: bigint): string {
    return new Intl.NumberFormat("fr-CA", {
        style: "currency",
        currency: "USD",
    }).format(Number(priceInCents) / 100);
}
