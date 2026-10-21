\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on

SELECT min(customer_id) AS cust_ok FROM core.customers WHERE kyc_status = 'VERIFIED' \gset
SELECT min(customer_id) AS cust_ko FROM core.customers WHERE kyc_status <> 'VERIFIED' \gset
SELECT min(account_id) AS acc_a FROM core.accounts WHERE status = 'ACTIVE' AND balance > 10000 \gset
SELECT min(account_id) AS acc_b FROM core.accounts WHERE status = 'ACTIVE' AND account_id > :acc_a \gset
SELECT min(account_id) AS acc_frozen FROM core.accounts WHERE status = 'FROZEN' \gset

BEGIN;

\echo ''
\echo '################ E2 : CONTRAINTES ################'
\echo '[DOIT REUSSIR] client valide'
INSERT INTO core.customers (first_name, last_name, email, birth_date)
VALUES ('Test', 'Ok', 'test.ok@novabank.fr', '1990-05-01');
\echo '[DOIT ECHOUER] email invalide'
INSERT INTO core.customers (first_name, last_name, email, birth_date)
VALUES ('Test', 'Ko', 'pas-un-email', '1990-05-01');
\echo '[DOIT ECHOUER] email deja utilise'
INSERT INTO core.customers (first_name, last_name, email, birth_date)
VALUES ('Test', 'Ko', 'client1@novabank.fr', '1990-05-01');
\echo '[DOIT ECHOUER] solde negatif'
UPDATE core.accounts SET balance = -1 WHERE account_id = :acc_a;
\echo '[DOIT ECHOUER] IBAN deja utilise'
INSERT INTO core.accounts (customer_id, iban) VALUES (1, 'FR7600000000000000000000001');
\echo '[DOIT ECHOUER] virement vers le meme compte'
INSERT INTO core.transfers (from_account_id, to_account_id, amount) VALUES (:acc_a, :acc_a, 10);
\echo '[DOIT ECHOUER] virement de montant negatif'
INSERT INTO core.transfers (from_account_id, to_account_id, amount) VALUES (:acc_a, :acc_b, -10);

\echo ''
\echo '################ E3 : DROITS ################'
SET ROLE support1;
\echo '[DOIT REUSSIR] support lit les comptes'
SELECT count(*) FROM core.accounts;
\echo '[DOIT ECHOUER] support lit les emails'
SELECT email FROM core.customers LIMIT 1;
RESET ROLE;

SET ROLE analyst1;
\echo '[DOIT REUSSIR] analyste lit les ecritures'
SELECT count(*) FROM core.transactions;
\echo '[DOIT ECHOUER] analyste modifie un solde'
UPDATE core.accounts SET balance = 0 WHERE account_id = :acc_a;
\echo '[DOIT ECHOUER] analyste lit le journal d audit'
SELECT count(*) FROM audit.audit_log;
RESET ROLE;

SET ROLE auditor1;
\echo '[DOIT REUSSIR] auditeur lit le journal d audit'
SELECT count(*) FROM audit.audit_log;
\echo '[DOIT ECHOUER] auditeur supprime les alertes'
DELETE FROM core.fraud_alerts;
RESET ROLE;

SET ROLE app_user;
\echo '[DOIT ECHOUER] application lit une table directement'
SELECT count(*) FROM core.accounts;
RESET ROLE;

\echo ''
\echo '################ E4 : VUES ################'
SET ROLE support1;
\echo '[DOIT REUSSIR] support lit les clients masques'
SELECT customer_id, first_name, last_name, email, phone FROM core.v_customers_masked LIMIT 3;
\echo '[DOIT REUSSIR] support gele un compte'
UPDATE core.v_accounts_support SET status = 'FROZEN' WHERE account_id = :acc_b;
\echo '[DOIT ECHOUER] support ferme un compte (CHECK OPTION)'
UPDATE core.v_accounts_support SET status = 'CLOSED' WHERE account_id = :acc_b;
\echo '[DOIT ECHOUER] support modifie un IBAN'
UPDATE core.v_accounts_support SET iban = 'FR7600000000000000000099999' WHERE account_id = :acc_b;
UPDATE core.v_accounts_support SET status = 'ACTIVE' WHERE account_id = :acc_b;
RESET ROLE;
SET ROLE analyst1;
\echo '[DOIT REUSSIR] analyste lit la vue enregistree'
SELECT * FROM core.mv_monthly_stats ORDER BY month DESC, tx_type LIMIT 4;
RESET ROLE;

\echo ''
\echo '################ E6 : TRIGGERS ################'
\echo '[DOIT REUSSIR] depot, balance_after calcule automatiquement'
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (:acc_a, 'DEPOSIT', 100) RETURNING tx_id, amount, balance_after;
\echo '[DOIT ECHOUER] retrait superieur au solde'
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (:acc_a, 'WITHDRAWAL', -99999999);
\echo '[DOIT ECHOUER] modifier le grand livre'
UPDATE core.transactions SET amount = 1 WHERE tx_id = 1;
\echo '[DOIT ECHOUER] supprimer dans le grand livre'
DELETE FROM core.transactions WHERE tx_id = 1;
\echo '[DOIT ECHOUER] vider le grand livre'
TRUNCATE core.transactions CASCADE;
\echo '[DOIT ECHOUER] client mineur'
INSERT INTO core.customers (first_name, last_name, email, birth_date)
VALUES ('Jeune', 'Test', 'jeune@novabank.fr', current_date - interval '10 years');
\echo '[DOIT REUSSIR] alerte sur un retrait de 5000'
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (:acc_a, 'WITHDRAWAL', -5000);
SELECT account_id, rule_code FROM core.fraud_alerts ORDER BY alert_id DESC LIMIT 1;
\echo '[DOIT REUSSIR] changements notes dans le journal d audit'
SELECT table_name, operation, db_user FROM audit.audit_log ORDER BY log_id DESC LIMIT 3;

\echo ''
\echo '################ E7 : PROCEDURES ################'
SET ROLE app_user;
\echo '[DOIT REUSSIR] ouverture de compte'
CALL core.sp_open_account(:cust_ok, 'SAVINGS', 500, NULL, NULL);
\echo '[DOIT ECHOUER] ouverture pour un client non verifie'
CALL core.sp_open_account(:cust_ko, 'SAVINGS', 500, NULL, NULL);
\echo '[DOIT REUSSIR] virement'
CALL core.sp_transfer(:acc_a, :acc_b, 250, 'Test E8', NULL);
\echo '[DOIT REUSSIR] releve'
SELECT * FROM core.fn_statement(:acc_a, 3);
\echo '[DOIT ECHOUER] virement vers le meme compte'
CALL core.sp_transfer(:acc_a, :acc_a, 10, NULL, NULL);
\echo '[DOIT ECHOUER] virement negatif'
CALL core.sp_transfer(:acc_a, :acc_b, -5, NULL, NULL);
\echo '[DOIT ECHOUER] virement trop gros'
CALL core.sp_transfer(:acc_a, :acc_b, 99999999, NULL, NULL);
\echo '[DOIT ECHOUER] virement vers un compte gele'
CALL core.sp_transfer(:acc_a, :acc_frozen, 10, NULL, NULL);
\echo '[DOIT ECHOUER] virement vers un compte inexistant'
CALL core.sp_transfer(:acc_a, 999999999, 10, NULL, NULL);
\echo '[DOIT REUSSIR] 4 virements de plus : alerte 5 virements en 10 minutes'
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale', NULL);
RESET ROLE;
SELECT account_id, rule_code FROM core.fraud_alerts ORDER BY alert_id DESC LIMIT 1;

\echo ''
\echo '################ COHERENCE APRES TOUS LES TESTS ################'
\i sql/03_check.sql

ROLLBACK;
\echo ''
\echo '################ ROLLBACK : la base est revenue a son etat initial ################'
