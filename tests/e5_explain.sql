\echo '=== 1. Releve du compte 42'
EXPLAIN (ANALYZE, BUFFERS)
SELECT tx_id, tx_type, amount, balance_after, created_at
FROM core.transactions
WHERE account_id = 42
ORDER BY created_at DESC
LIMIT 50;

\echo '=== 2. Recherche email insensible a la casse'
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, first_name, last_name
FROM core.customers
WHERE lower(email) = lower('Client4242@NovaBank.fr');

\echo '=== 3. Comptes geles'
EXPLAIN (ANALYZE, BUFFERS)
SELECT account_id, customer_id, balance
FROM core.accounts
WHERE status = 'FROZEN';

\echo '=== 4. Somme des operations de janvier 2026'
EXPLAIN (ANALYZE, BUFFERS)
SELECT tx_type, sum(amount)
FROM core.transactions
WHERE created_at >= '2026-01-01' AND created_at < '2026-02-01'
GROUP BY tx_type;

