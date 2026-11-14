const pages = [
    { id: 'dashboard', label: 'Tableau de bord' },
    { id: 'lend', label: 'Prêter' },
    { id: 'borrow', label: 'Emprunter' },
    { id: 'liquidate', label: 'Liquider' },
] as const;

export type PageId = (typeof pages)[number]['id'];

export function Navigation({
    current,
    onChange,
}: {
    current: PageId;
    onChange: (page: PageId) => void;
}) {
    return (
        <nav
            className="nav nav-pills flex-nowrap gap-1 overflow-auto"
            aria-label="Navigation principale"
        >
            {pages.map(({ id, label }) => (
                <button
                    key={id}
                    className={`nav-link text-nowrap${current === id ? ' active' : ''}`}
                    type="button"
                    aria-current={current === id ? 'page' : undefined}
                    onClick={() => onChange(id)}
                >
                    {label}
                </button>
            ))}
        </nav>
    );
}
