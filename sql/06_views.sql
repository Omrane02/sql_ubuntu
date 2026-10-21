BEGIN;

CREATE VIEW core.v_customers_masked
WITH (security_barrier = true) AS
SELECT
    customer_id,
    left(md5(email), 12)                                         AS client_ref,
    first_name,
    left(last_name, 1) || '.'                                    AS last_name,
    left(email, 1) || '***' || substr(email, strpos(email, '@')) AS email,
    CASE WHEN phone IS NULL THEN NULL
         ELSE '** ** ** ** ' || right(phone, 2) END              AS phone,
    extract(year FROM birth_date)::int                           AS birth_year,
    kyc_status,
    risk_level,
    created_at
FROM core.customers;

CREATE VIEW core.v_accounts_support
WITH (security_barrier = true) AS
SELECT account_id, customer_id, iban, account_type, status, opened_at
FROM core.accounts
WHERE status IN ('ACTIVE', 'FROZEN')
WITH LOCAL CHECK OPTION;

CREATE MATERIALIZED VIEW core.mv_monthly_stats AS
SELECT date_trunc('month', created_at)::date AS month,
       tx_type,
       count(*)                              AS nb_operations,
       sum(amount)                           AS total,
       round(avg(amount), 2)                 AS moyenne
FROM core.transactions
GROUP BY 1, 2
WITH NO DATA;

CREATE UNIQUE INDEX ux_mv_monthly_stats ON core.mv_monthly_stats (month, tx_type);

REFRESH MATERIALIZED VIEW core.mv_monthly_stats;

GRANT SELECT ON core.v_customers_masked TO g_support, g_analyst;
GRANT SELECT, UPDATE (status) ON core.v_accounts_support TO g_support;
GRANT SELECT ON core.mv_monthly_stats TO g_analyst, g_auditor;

COMMIT;
