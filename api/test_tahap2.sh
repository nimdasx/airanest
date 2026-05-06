#!/bin/bash
# Test script untuk memastikan Tahap 2 (Database Models & Migrations) berjalan dengan baik.
# Jalankan dari folder api/: ./test_tahap2.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [ "$result" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== AiraNest API — Test Tahap 2 ==="
echo ""

# 1. Check migration ran successfully on startup
echo "[Alembic Migration]"
MIGRATION_LOG=$(docker compose logs api 2>&1 | grep -c "Running upgrade")
check "Migration ran on container start" $([ "$MIGRATION_LOG" -ge 1 ] && echo 0 || echo 1)

MIGRATION_ERROR=$(docker compose logs api 2>&1 | grep -ci "error\|traceback" || true)
check "No migration errors in logs" $([ "$MIGRATION_ERROR" -eq 0 ] && echo 0 || echo 1)

ALEMBIC_HEAD=$(docker compose exec -T api alembic current 2>&1 | grep -c "head")
check "Alembic is at head revision" $([ "$ALEMBIC_HEAD" -ge 1 ] && echo 0 || echo 1)

echo ""

# 2. Check all expected tables exist
echo "[Database Tables]"
EXPECTED_TABLES="users mail_accounts messages attachments sync_logs alembic_version"
for table in $EXPECTED_TABLES; do
    EXISTS=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='$table'" 2>/dev/null | tr -d ' ')
    check "Table '$table' exists" $([ "$EXISTS" = "1" ] && echo 0 || echo 1)
done

echo ""

# 3. Check key columns exist in tables
echo "[Table Columns]"

# users
USER_COLS=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT column_name FROM information_schema.columns WHERE table_name='users' ORDER BY column_name" 2>/dev/null)
for col in id email password_hash created_at updated_at; do
    check "users.$col exists" $(echo "$USER_COLS" | grep -qw "$col" && echo 0 || echo 1)
done

# mail_accounts
MA_COLS=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT column_name FROM information_schema.columns WHERE table_name='mail_accounts' ORDER BY column_name" 2>/dev/null)
for col in id user_id imap_host imap_password_encrypted smtp_host delete_from_server last_uid uid_validity is_active; do
    check "mail_accounts.$col exists" $(echo "$MA_COLS" | grep -qw "$col" && echo 0 || echo 1)
done

# messages
MSG_COLS=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT column_name FROM information_schema.columns WHERE table_name='messages' ORDER BY column_name" 2>/dev/null)
for col in id user_id mail_account_id imap_uid message_id_header from_addr subject body_text body_html is_read is_starred is_deleted_from_server fingerprint; do
    check "messages.$col exists" $(echo "$MSG_COLS" | grep -qw "$col" && echo 0 || echo 1)
done

# attachments
ATT_COLS=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT column_name FROM information_schema.columns WHERE table_name='attachments' ORDER BY column_name" 2>/dev/null)
for col in id message_id filename mime_type file_size storage_path; do
    check "attachments.$col exists" $(echo "$ATT_COLS" | grep -qw "$col" && echo 0 || echo 1)
done

# sync_logs
SL_COLS=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT column_name FROM information_schema.columns WHERE table_name='sync_logs' ORDER BY column_name" 2>/dev/null)
for col in id mail_account_id started_at ended_at status messages_fetched messages_deleted_from_server error_message; do
    check "sync_logs.$col exists" $(echo "$SL_COLS" | grep -qw "$col" && echo 0 || echo 1)
done

echo ""

# 4. Check indexes exist
echo "[Indexes]"
INDEXES=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT indexname FROM pg_indexes WHERE schemaname='public'" 2>/dev/null)
for idx in ix_users_email ix_mail_accounts_user_id ix_messages_user_id ix_messages_mail_account_id ix_messages_message_id_header ix_messages_received_at ix_attachments_message_id ix_sync_logs_mail_account_id; do
    check "Index $idx exists" $(echo "$INDEXES" | grep -qw "$idx" && echo 0 || echo 1)
done

echo ""

# 5. Check foreign keys
echo "[Foreign Keys]"
FK_COUNT=$(docker compose exec -T postgres psql -U airanest -t -c "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type='FOREIGN KEY'" 2>/dev/null | tr -d ' ')
check "Foreign keys exist ($FK_COUNT found)" $([ "$FK_COUNT" -ge 5 ] && echo 0 || echo 1)

echo ""

# Summary
echo "=== Hasil ==="
echo -e "  ${GREEN}Passed: $PASS${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAIL${NC}"
    exit 1
else
    echo -e "  Failed: 0"
    echo ""
    echo "Tahap 2 OK!"
fi
