#!/usr/bin/env bash
# Verifies a participant's laptop is ready for the workshop. Run from the repository root:
#   ./scripts/check-setup.sh
# (Windows: run it in WSL2 or Git Bash. Without bash, just run the three commands in PREREQUISITES.md.)
set -u
cd "$(dirname "$0")/.."
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✘\033[0m %s\n' "$1"; FAILED=1; }
FAILED=0

echo "1/4 Docker"
command -v docker >/dev/null 2>&1 && ok "docker found: $(docker --version)" || { fail "docker not installed - see PREREQUISITES.md"; exit 1; }
docker info >/dev/null 2>&1 && ok "docker daemon is running" || { fail "docker daemon not running - start Docker Desktop and retry"; exit 1; }
docker compose version >/dev/null 2>&1 && ok "docker compose v2 available" || fail "docker compose v2 missing - update Docker Desktop"

echo "2/4 Starting PostgreSQL and MongoDB (first run downloads about 1 GB - do this on good wifi BEFORE the workshop)"
docker compose up -d --wait >/dev/null 2>&1 && ok "containers are healthy" || { fail "containers failed to start: run 'docker compose logs'"; exit 1; }

echo "3/4 PostgreSQL"
v=$(docker compose exec -T postgres psql -U workshop -d saas -Atc "select version()" 2>/dev/null)
[ -n "$v" ] && ok "$(echo "$v" | cut -c1-40)" || fail "cannot query PostgreSQL"
docker compose exec -T postgres psql -U workshop -d saas -Atc "select 1" >/dev/null 2>&1 || fail "psql query failed"

echo "4/4 MongoDB"
m=$(docker compose exec -T mongo mongosh --quiet --eval "db.version()" 2>/dev/null)
[ -n "$m" ] && ok "MongoDB $m" || fail "cannot query MongoDB"

echo
if [ "$FAILED" = 0 ]; then echo "All good - you are ready for the workshop."; else echo "Something failed - send the output above to the instructor."; exit 1; fi
