\echo '=== Contrôle 1 : solde du compte = dernier balance_after = somme des écritures'
WITH last AS (
    SELECT DISTINCT ON (account_id) account_id, balance_after
    FROM core.transactions
    ORDER BY account_id, tx_id DESC
),
sums AS (
    SELECT account_id, sum(amount) AS total
    FROM core.transactions
    GROUP BY account_id
)
SELECT a.account_id, a.balance, l.balance_after, s.total
FROM core.accounts AS a
LEFT JOIN last AS l USING (account_id)
LEFT JOIN sums AS s USING (account_id)
WHERE a.balance IS DISTINCT FROM l.balance_after
   OR a.balance IS DISTINCT FROM s.total;

\echo '=== Contrôle 2 : chaque virement a exactement 2 écritures qui s annulent'
SELECT t.transfer_id, count(x.tx_id) AS nb_ecritures, sum(x.amount) AS somme
FROM core.transfers AS t
LEFT JOIN core.transactions AS x USING (transfer_id)
GROUP BY t.transfer_id
HAVING count(x.tx_id) <> 2
    OR sum(x.amount) <> 0;

\echo '=== Contrôle 3 : aucun solde négatif, ni sur un compte, ni dans l historique'
SELECT 'compte' AS ou, account_id, balance AS valeur
FROM core.accounts WHERE balance < 0
UNION ALL
SELECT 'ecriture', account_id, balance_after
FROM core.transactions WHERE balance_after < 0;
