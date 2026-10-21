CREATE INDEX ix_tx_account_created ON core.transactions (account_id, created_at DESC);

CREATE INDEX ix_customers_email_lower ON core.customers (lower(email));

CREATE INDEX ix_accounts_frozen ON core.accounts (account_id) WHERE status = 'FROZEN';

CREATE INDEX brin_tx_created ON core.transactions USING brin (created_at);

ANALYZE core.transactions, core.customers, core.accounts;
