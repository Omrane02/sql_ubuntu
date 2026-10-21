SELECT account_id AS acc FROM core.accounts
WHERE status = 'ACTIVE' AND balance > 10000
ORDER BY account_id LIMIT 1 \gset

\echo '=== 1. Solde mis a jour automatiquement'
SELECT account_id, balance FROM core.accounts WHERE account_id = :acc;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (:acc, 'DEPOSIT', 100)
RETURNING tx_id, amount, balance_after;
SELECT account_id, balance FROM core.accounts WHERE account_id = :acc;

\echo '=== 2. Solde insuffisant refuse'
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (:acc, 'WITHDRAWAL', -99999999);

\echo '=== 3. Historique non modifiable'
UPDATE core.transactions SET amount = 1 WHERE tx_id = 1;
DELETE FROM core.transactions WHERE tx_id = 1;
TRUNCATE core.transactions CASCADE;

\echo '=== 4. Alerte gros retrait'
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (:acc, 'WITHDRAWAL', -5000);
SELECT * FROM core.fraud_alerts ORDER BY alert_id DESC LIMIT 1;

\echo '=== 5. Client mineur refuse'
INSERT INTO core.customers (first_name, last_name, email, birth_date)
VALUES ('Jeune', 'Test', 'jeune@novabank.fr', current_date - interval '10 years');

\echo '=== 6. Journal d audit'
SELECT log_id, table_name, operation,
       old_data->>'balance' AS ancien_solde,
       new_data->>'balance' AS nouveau_solde,
       db_user, changed_at
FROM audit.audit_log
ORDER BY log_id DESC LIMIT 4;
