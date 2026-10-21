BEGIN;

CREATE FUNCTION core.fn_tx_apply_balance() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_balance numeric(14,2);
    v_status  core.account_status;
BEGIN
    SELECT balance, status INTO v_balance, v_status
    FROM core.accounts
    WHERE account_id = NEW.account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compte % inexistant', NEW.account_id;
    END IF;

    IF v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Compte % non actif (statut %)', NEW.account_id, v_status;
    END IF;

    NEW.balance_after := v_balance + NEW.amount;

    IF NEW.balance_after < 0 THEN
        RAISE EXCEPTION 'Solde insuffisant sur le compte % : solde %, operation %',
            NEW.account_id, v_balance, NEW.amount;
    END IF;

    UPDATE core.accounts SET balance = NEW.balance_after WHERE account_id = NEW.account_id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transactions_before_insert_balance
    BEFORE INSERT ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_tx_apply_balance();


CREATE FUNCTION core.fn_forbid_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Table %.% : % interdit, l historique ne se modifie pas',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP;
END;
$$;

CREATE TRIGGER trg_transactions_before_update_delete_immutable
    BEFORE UPDATE OR DELETE ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_forbid_change();

CREATE TRIGGER trg_transactions_before_truncate_immutable
    BEFORE TRUNCATE ON core.transactions
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_forbid_change();

CREATE TRIGGER trg_audit_log_before_update_delete_immutable
    BEFORE UPDATE OR DELETE ON audit.audit_log
    FOR EACH ROW EXECUTE FUNCTION core.fn_forbid_change();

CREATE TRIGGER trg_audit_log_before_truncate_immutable
    BEFORE TRUNCATE ON audit.audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_forbid_change();


CREATE FUNCTION core.fn_tx_fraud() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_count int;
BEGIN
    IF NEW.tx_type = 'WITHDRAWAL' AND NEW.amount <= -5000 THEN
        INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
        VALUES (NEW.account_id, NEW.tx_id, 'BIG_WITHDRAWAL');
    END IF;

    IF NEW.tx_type = 'TRANSFER_OUT' THEN
        SELECT count(*) INTO v_count
        FROM core.transactions
        WHERE account_id = NEW.account_id
          AND tx_type = 'TRANSFER_OUT'
          AND created_at >  NEW.created_at - interval '10 minutes'
          AND created_at <= NEW.created_at;

        IF v_count >= 5 AND NOT EXISTS (
            SELECT 1 FROM core.fraud_alerts
            WHERE account_id = NEW.account_id
              AND rule_code = 'TRANSFER_BURST'
              AND created_at > NEW.created_at - interval '10 minutes'
        ) THEN
            INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
            VALUES (NEW.account_id, NEW.tx_id, 'TRANSFER_BURST');
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_transactions_after_insert_fraud
    AFTER INSERT ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_tx_fraud();


CREATE FUNCTION audit.fn_audit() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    INSERT INTO audit.audit_log (table_name, operation, old_data, new_data, db_user)
    VALUES (
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END,
        session_user
    );
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_customers_after_write_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.customers
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit();

CREATE TRIGGER trg_accounts_after_write_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.accounts
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit();

CREATE TRIGGER trg_fraud_alerts_after_write_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.fraud_alerts
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit();


CREATE FUNCTION core.fn_customer_adult() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.birth_date > current_date - interval '18 years' THEN
        RAISE EXCEPTION 'Client mineur refuse : ne le %', NEW.birth_date;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_before_write_adult
    BEFORE INSERT OR UPDATE OF birth_date ON core.customers
    FOR EACH ROW EXECUTE FUNCTION core.fn_customer_adult();

COMMIT;
