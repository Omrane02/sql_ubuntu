SELECT min(customer_id) AS cust_ok FROM core.customers WHERE kyc_status = 'VERIFIED' \gset
SELECT min(customer_id) AS cust_ko FROM core.customers WHERE kyc_status <> 'VERIFIED' \gset
SELECT min(account_id) AS acc_a FROM core.accounts WHERE status = 'ACTIVE' AND balance > 10000 \gset
SELECT min(account_id) AS acc_b FROM core.accounts WHERE status = 'ACTIVE' AND account_id > :acc_a \gset
SELECT min(account_id) AS acc_frozen FROM core.accounts WHERE status = 'FROZEN' \gset

SET ROLE app_user;

\echo '=== 1. L application n a aucun acces direct aux tables'
SELECT count(*) FROM core.accounts;
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (:acc_a, 'DEPOSIT', 1000000);

\echo '=== 2. Ouverture de compte : acceptee puis refusee (KYC)'
CALL core.sp_open_account(:cust_ok, 'SAVINGS', 500, NULL, NULL);
CALL core.sp_open_account(:cust_ko, 'SAVINGS', 500, NULL, NULL);

\echo '=== 3. Virement accepte et releve'
CALL core.sp_transfer(:acc_a, :acc_b, 250, 'Test E7', NULL);
SELECT * FROM core.fn_statement(:acc_a, 3);
SELECT * FROM core.fn_statement(:acc_b, 3);

\echo '=== 4. Virements refuses'
CALL core.sp_transfer(:acc_a, :acc_a, 10, 'Meme compte', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, -5, 'Negatif', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 10.555, 'Trop de decimales', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 99999999, 'Trop cher', NULL);
CALL core.sp_transfer(:acc_a, :acc_frozen, 10, 'Vers compte gele', NULL);
CALL core.sp_transfer(:acc_a, 999999999, 10, 'Compte inconnu', NULL);

\echo '=== 5. Fraude : 4 virements de plus, soit 5 en 10 minutes'
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale 2', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale 3', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale 4', NULL);
CALL core.sp_transfer(:acc_a, :acc_b, 10, 'Rafale 5', NULL);

RESET ROLE;
SELECT alert_id, account_id, tx_id, rule_code, status, created_at
FROM core.fraud_alerts ORDER BY alert_id DESC LIMIT 2;
