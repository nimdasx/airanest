#!/bin/bash
# Test script untuk memastikan Tahap 1 (Project Skeleton & Docker Setup) berjalan dengan baik.
# Jalankan dari folder api/: ./test_tahap1.sh

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
echo "=== AiraNest API — Test Tahap 1 ==="
echo ""

# 1. Check all containers are running
echo "[Containers]"

docker compose ps --format '{{.Service}} {{.State}}' | while read service state; do
    if [ "$state" = "running" ]; then
        echo -e "  ${GREEN}✓${NC} $service is running"
    else
        echo -e "  ${RED}✗${NC} $service is $state"
    fi
done

EXPECTED_SERVICES="api worker beat postgres redis"
for svc in $EXPECTED_SERVICES; do
    state=$(docker compose ps --format '{{.Service}} {{.State}}' | grep "^$svc " | awk '{print $2}')
    check "$svc container exists and running" $([ "$state" = "running" ] && echo 0 || echo 1)
done

echo ""

# 2. Health check endpoint
echo "[API Health Check]"
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null)
check "GET /health returns 200" $([ "$HEALTH" = "200" ] && echo 0 || echo 1)

BODY=$(curl -s http://localhost:8000/health 2>/dev/null)
check "Response contains status ok" $(echo "$BODY" | grep -q '"status":"ok"' && echo 0 || echo 1)
check "Response contains app name AiraNest" $(echo "$BODY" | grep -q 'AiraNest' && echo 0 || echo 1)

echo ""

# 3. PostgreSQL healthy
echo "[PostgreSQL]"
PG_READY=$(docker compose exec -T postgres pg_isready -U airanest 2>/dev/null | grep -c "accepting connections")
check "PostgreSQL accepting connections" $([ "$PG_READY" -ge 1 ] && echo 0 || echo 1)

echo ""

# 4. Redis healthy
echo "[Redis]"
REDIS_PONG=$(docker compose exec -T redis redis-cli ping 2>/dev/null)
check "Redis responds PONG" $([ "$REDIS_PONG" = "PONG" ] && echo 0 || echo 1)

echo ""

# 5. Celery worker ready
echo "[Celery Worker]"
WORKER_READY=$(docker compose logs worker 2>&1 | grep -c "ready\.")
check "Worker is ready" $([ "$WORKER_READY" -ge 1 ] && echo 0 || echo 1)

echo ""

# 6. Celery beat started
echo "[Celery Beat]"
BEAT_STARTED=$(docker compose logs beat 2>&1 | grep -c "beat: Starting")
check "Beat is started" $([ "$BEAT_STARTED" -ge 1 ] && echo 0 || echo 1)

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
    echo "Tahap 1 OK!"
fi
