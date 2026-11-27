export const pages = [
    { id: 'dashboard', label: 'Tableau de bord', requiresWallet: false },
    { id: 'lend', label: 'Prêter', requiresWallet: true },
    { id: 'borrow', label: 'Emprunter', requiresWallet: true },
    { id: 'liquidate', label: 'Liquider', requiresWallet: true },
    { id: 'faucet', label: 'Faucet', requiresWallet: true },
] as const;

export type PageId = (typeof pages)[number]['id'];
