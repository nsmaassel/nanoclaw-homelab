#!/usr/bin/env bash
# create-db-user.sh — Create nanoclaw_reader read-only Postgres user
# Run once against the data-lake postgres pod.
set -euo pipefail

NAMESPACE=data-lake
POD=postgres-0
CONTAINER=postgres
DB_USER=datauser
DB_NAME=data_lake

# Generate a random password if not provided
READER_PASSWORD="${NANOCLAW_DB_PASSWORD:-$(openssl rand -base64 24 | tr -d '=+/' | head -c 20)}"

echo "Creating nanoclaw_reader user in $DB_NAME..."
echo "Password: $READER_PASSWORD  ← save this for create-secrets.sh"
echo ""

kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" -- psql -U "$DB_USER" -d "$DB_NAME" <<SQL
-- Create read-only user for Nanoclaw agent
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'nanoclaw_reader') THEN
    CREATE ROLE nanoclaw_reader WITH LOGIN PASSWORD '$READER_PASSWORD' NOINHERIT;
    RAISE NOTICE 'Created nanoclaw_reader role';
  ELSE
    ALTER ROLE nanoclaw_reader WITH PASSWORD '$READER_PASSWORD';
    RAISE NOTICE 'Updated nanoclaw_reader password';
  END IF;
END
\$\$;

-- Grant read access to silver and gold schemas only
-- (no access to bronze raw data)
GRANT CONNECT ON DATABASE $DB_NAME TO nanoclaw_reader;
GRANT USAGE ON SCHEMA silver TO nanoclaw_reader;
GRANT USAGE ON SCHEMA gold TO nanoclaw_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA silver TO nanoclaw_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO nanoclaw_reader;

-- Ensure future tables are accessible too
ALTER DEFAULT PRIVILEGES IN SCHEMA silver GRANT SELECT ON TABLES TO nanoclaw_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold GRANT SELECT ON TABLES TO nanoclaw_reader;

SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = 'nanoclaw_reader';
SQL

echo ""
echo "✅ nanoclaw_reader created"
echo ""
echo "Next: run create-secrets.sh with NANOCLAW_DB_PASSWORD=$READER_PASSWORD"
echo "Or export it: export NANOCLAW_DB_PASSWORD='$READER_PASSWORD'"
