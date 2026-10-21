BEGIN;

CREATE PROCEDURE core.sp_transfer(
    p_from_account_id   bigint,
    p_to_account_id     bigint,
    p_amount            numeric,
    p_label             varchar DEFAULT NULL,
    INOUT p_transfer_id bigint  DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_from_status  core.account_status;
    v_to_status    core.account_status;
    v_from_balance numeric(14,2);
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Virement refuse : montant % invalide, il doit etre positif', p_amount;
    END IF;

    IF p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Virement refuse : montant % invalide, 2 decimales maximum', p_amount;
    END IF;

    IF p_from_account_id IS NULL OR p_to_account_id IS NULL THEN
        RAISE EXCEPTION 'Virement refuse : compte emetteur et destinataire obligatoires';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'Virement refuse : les deux comptes sont identiques (%)', p_from_account_id;
    END IF;

    PERFORM 1
    FROM core.accounts
    WHERE account_id IN (p_from_account_id, p_to_account_id)
    ORDER BY account_id
    FOR UPDATE;

    SELECT status, balance INTO v_from_status, v_from_balance
    FROM core.accounts WHERE account_id = p_from_account_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Virement refuse : compte emetteur % inexistant', p_from_account_id;
    END IF;

    SELECT status INTO v_to_status
    FROM core.accounts WHERE account_id = p_to_account_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Virement refuse : compte destinataire % inexistant', p_to_account_id;
    END IF;

    IF v_from_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Virement refuse : compte emetteur % non actif (%)', p_from_account_id, v_from_status;
    END IF;

    IF v_to_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Virement refuse : compte destinataire % non actif (%)', p_to_account_id, v_to_status;
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'Virement refuse : solde insuffisant (% disponible, % demande)', v_from_balance, p_amount;
    END IF;

    INSERT INTO core.transfers (from_account_id, to_account_id, amount, label)
    VALUES (p_from_account_id, p_to_account_id, p_amount, p_label)
    RETURNING transfer_id INTO p_transfer_id;

    INSERT INTO core.transactions (account_id, tx_type, amount, transfer_id)
    VALUES (p_from_account_id, 'TRANSFER_OUT', -p_amount, p_transfer_id),
           (p_to_account_id,   'TRANSFER_IN',   p_amount, p_transfer_id);
END;
$$;


CREATE SEQUENCE core.iban_seq START WITH 100001;

CREATE PROCEDURE core.sp_open_account(
    p_customer_id      bigint,
    p_account_type     core.account_type DEFAULT 'CHECKING',
    p_initial_deposit  numeric           DEFAULT 0,
    INOUT p_account_id bigint            DEFAULT NULL,
    INOUT p_iban       varchar           DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_kyc core.kyc_status;
BEGIN
    IF p_initial_deposit IS NULL OR p_initial_deposit < 0
       OR p_initial_deposit <> round(p_initial_deposit, 2) THEN
        RAISE EXCEPTION 'Ouverture refusee : depot initial % invalide', p_initial_deposit;
    END IF;

    SELECT kyc_status INTO v_kyc
    FROM core.customers WHERE customer_id = p_customer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ouverture refusee : client % inexistant', p_customer_id;
    END IF;

    IF v_kyc <> 'VERIFIED' THEN
        RAISE EXCEPTION 'Ouverture refusee : identite du client % non verifiee (KYC %)', p_customer_id, v_kyc;
    END IF;

    INSERT INTO core.accounts (customer_id, iban, account_type)
    VALUES (p_customer_id,
            'FR76' || lpad(nextval('core.iban_seq')::text, 23, '0'),
            p_account_type)
    RETURNING account_id, iban INTO p_account_id, p_iban;

    IF p_initial_deposit > 0 THEN
        INSERT INTO core.transactions (account_id, tx_type, amount)
        VALUES (p_account_id, 'DEPOSIT', p_initial_deposit);
    END IF;
END;
$$;


CREATE FUNCTION core.fn_statement(p_account_id bigint, p_limit int DEFAULT 50)
RETURNS TABLE (
    tx_id         bigint,
    created_at    timestamptz,
    tx_type       core.tx_type,
    amount        numeric,
    balance_after numeric,
    label         varchar
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.accounts AS a WHERE a.account_id = p_account_id) THEN
        RAISE EXCEPTION 'Releve refuse : compte % inexistant', p_account_id;
    END IF;

    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN
        RAISE EXCEPTION 'Releve refuse : nombre de lignes entre 1 et 500';
    END IF;

    RETURN QUERY
    SELECT t.tx_id, t.created_at, t.tx_type, t.amount, t.balance_after, tr.label
    FROM core.transactions AS t
    LEFT JOIN core.transfers AS tr ON tr.transfer_id = t.transfer_id
    WHERE t.account_id = p_account_id
    ORDER BY t.created_at DESC, t.tx_id DESC
    LIMIT p_limit;
END;
$$;


GRANT EXECUTE ON PROCEDURE core.sp_transfer     TO g_app;
GRANT EXECUTE ON PROCEDURE core.sp_open_account TO g_app;
GRANT EXECUTE ON FUNCTION  core.fn_statement    TO g_app, g_support;

COMMIT;
