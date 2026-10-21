CREATE ROLE g_analyst NOLOGIN;
CREATE ROLE g_support NOLOGIN;
CREATE ROLE g_auditor NOLOGIN;
CREATE ROLE g_app     NOLOGIN;

CREATE ROLE analyst1 LOGIN IN ROLE g_analyst;
CREATE ROLE support1 LOGIN IN ROLE g_support;
CREATE ROLE auditor1 LOGIN IN ROLE g_auditor;
CREATE ROLE app_user LOGIN IN ROLE g_app;

ALTER ROLE analyst1 SET statement_timeout = '30s';
ALTER ROLE support1 SET statement_timeout = '5s';
ALTER ROLE auditor1 SET statement_timeout = '60s';
ALTER ROLE app_user SET statement_timeout = '3s';

REVOKE ALL ON DATABASE bankdb FROM PUBLIC;
GRANT CONNECT ON DATABASE bankdb TO g_analyst, g_support, g_auditor, g_app;
