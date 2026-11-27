import { pages, type PageId } from '../models/pageConfig';

export function Navigation({
    current,
    onChange,
    isWalletConnected,
}: {
    current: PageId;
    onChange: (page: PageId) => void;
    isWalletConnected: boolean;
}) {
    return (
        <nav
            className="nav nav-pills flex-nowrap gap-1 overflow-auto"
            aria-label="Navigation principale"
        >
            {pages.map(({ id, label, requiresWallet }) => (
                <button
                    key={id}
                    className={id === 'faucet'
                        ? `btn btn-sm text-nowrap ms-2 ${current === id ? 'btn-warning' : 'btn-outline-warning'}`
                        : `nav-link text-nowrap${current === id ? ' active' : ''}`}
                    type="button"
                    aria-current={current === id ? 'page' : undefined}
                    disabled={requiresWallet && !isWalletConnected}
                    onClick={() => onChange(id)}
                >
                    {label}
                </button>
            ))}
        </nav>
    );
}
