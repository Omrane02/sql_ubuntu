\timing on

BEGIN;

TRUNCATE core.transactions, core.transfers, core.fraud_alerts,
         core.accounts, core.customers, audit.audit_log
         RESTART IDENTITY;

SELECT setseed(0.42);


INSERT INTO core.customers
    (first_name, last_name, email, phone, birth_date, kyc_status, risk_level, created_at)
SELECT
    (ARRAY['Lea','Hugo','Emma','Louis','Chloe','Gabriel','Ines','Jules','Manon','Adam'])[1 + g % 10],
    (ARRAY['Martin','Bernard','Dubois','Thomas','Robert','Richard','Petit','Durand','Leroy','Moreau'])[1 + (g / 10) % 10],
    'client' || g || '@novabank.fr',
    '+33 6' || lpad(g::text, 8, '0'),

    DATE '1950-01-01' + floor(random() * (DATE '2005-12-31' - DATE '1950-01-01'))::int,
    (ARRAY['VERIFIED','VERIFIED','VERIFIED','PENDING','REJECTED']::core.kyc_status[])[1 + floor(random() * 5)::int],
    (ARRAY['LOW','LOW','LOW','MEDIUM','HIGH']::core.risk_level[])[1 + floor(random() * 5)::int],
    timestamptz '2023-01-01' + random() * interval '365 days'
FROM generate_series(1, 50000) AS g;


INSERT INTO core.accounts (customer_id, iban, account_type, status, opened_at)
SELECT
    1 + (g - 1) % 50000,
    'FR76' || lpad(g::text, 23, '0'),
    (ARRAY['CHECKING','SAVINGS','BUSINESS']::core.account_type[])[1 + g % 3],
    CASE WHEN random() < 0.02 THEN 'FROZEN' ELSE 'ACTIVE' END::core.account_status,
    timestamptz '2024-01-01' + random() * interval '180 days'
FROM generate_series(1, 100000) AS g;



INSERT INTO core.transfers (from_account_id, to_account_id, amount, label, created_at)
SELECT
    f,
    1 + (f + floor(random() * 99999)::int) % 100000,
    round((5 + random() * 995)::numeric, 2),
    (ARRAY['Loyer','Remboursement','Cadeau','Facture','Courses'])[1 + g % 5],
    timestamptz '2024-07-01' + random() * interval '820 days'
FROM (SELECT g, 1 + floor(random() * 100000)::int AS f
      FROM generate_series(1, 200000) AS g) AS s;

CREATE TEMP TABLE ops AS
    -- dépôt d'ouverture : la 1re opération de chaque compte
    SELECT account_id::bigint                        AS account_id,
           'DEPOSIT'::core.tx_type                   AS tx_type,
           round((10000 + random() * 50000)::numeric, 2) AS amount,
           NULL::bigint                              AS transfer_id,
           opened_at                                 AS created_at
    FROM core.accounts
UNION ALL
    -- virement, côté émetteur : montant négatif
    SELECT from_account_id, 'TRANSFER_OUT'::core.tx_type, -amount, transfer_id, created_at
    FROM core.transfers
UNION ALL
    -- virement, côté destinataire : montant positif
    SELECT to_account_id, 'TRANSFER_IN'::core.tx_type, amount, transfer_id, created_at
    FROM core.transfers
UNION ALL
    -- 250 000 dépôts
    SELECT 1 + floor(random() * 100000)::bigint, 'DEPOSIT'::core.tx_type,
           round((20 + random() * 2980)::numeric, 2), NULL,
           timestamptz '2024-07-01' + random() * interval '820 days'
    FROM generate_series(1, 250000)
UNION ALL
    -- 250 000 retraits : montant négatif
    SELECT 1 + floor(random() * 100000)::bigint, 'WITHDRAWAL'::core.tx_type,
           -round((10 + random() * 790)::numeric, 2), NULL,
           timestamptz '2024-07-01' + random() * interval '820 days'
    FROM generate_series(1, 250000);


INSERT INTO core.transactions (account_id, tx_type, amount, balance_after, transfer_id, created_at)
SELECT account_id, tx_type, amount,
       sum(amount) OVER (PARTITION BY account_id
                         ORDER BY created_at, amount DESC
                         ROWS UNBOUNDED PRECEDING),
       transfer_id, created_at
FROM ops
ORDER BY created_at, amount DESC;


UPDATE core.accounts AS a
SET    balance = t.balance_after
FROM  (SELECT DISTINCT ON (account_id) account_id, balance_after
       FROM core.transactions
       ORDER BY account_id, tx_id DESC) AS t
WHERE  a.account_id = t.account_id;

COMMIT;

ANALYZE core.customers, core.accounts, core.transfers, core.transactions;

SELECT 'customers'    AS table_name, count(*) FROM core.customers
UNION ALL SELECT 'accounts',     count(*) FROM core.accounts
UNION ALL SELECT 'transfers',    count(*) FROM core.transfers
UNION ALL SELECT 'transactions', count(*) FROM core.transactions;
