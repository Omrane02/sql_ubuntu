

BEGIN;


REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA core  FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM PUBLIC;


GRANT USAGE ON SCHEMA core  TO g_analyst, g_support, g_auditor, g_app;
GRANT USAGE ON SCHEMA audit TO g_auditor;


GRANT SELECT ON core.accounts, core.transfers, core.transactions TO g_analyst;

GRANT SELECT ON core.accounts TO g_support;


GRANT SELECT ON core.accounts, core.transfers, core.transactions, core.fraud_alerts
    TO g_auditor;
GRANT SELECT ON audit.audit_log TO g_auditor;

ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;


ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner IN SCHEMA audit
    GRANT SELECT ON TABLES TO g_auditor;

COMMIT;
