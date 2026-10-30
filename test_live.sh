#!/bin/bash
# test_live.sh — run the skink-mssql live integration test against a
# real Microsoft SQL Server in a podman container.
#
#   ./test_live.sh                      # start mssql/server:2022-latest, run, stop
#   SKINK_MSSQL_DSN=... ./test_live.sh  # against an existing server
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${MSSQL_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
PORT="${MSSQL_PORT:-11433}"
DSN="${SKINK_MSSQL_DSN:-}"
CONTAINER=""

SKINK_HOME="${SKINK_HOME:-$HOME/.local/skink/std}"
SKINK_BIN="${SKINK:-$(command -v skink || echo "$HOME/.local/skink/bin/skink")}"

cleanup() {
    [ -n "$CONTAINER" ] && podman rm -f "$CONTAINER" >/dev/null 2>&1
    rm -f "$SCRIPT_DIR/.live_test_bin"
}
trap cleanup EXIT

if [ -z "$DSN" ]; then
    if ! command -v podman >/dev/null 2>&1; then
        echo "SKIP: podman not available and SKINK_MSSQL_DSN unset"
        exit 0
    fi
    CONTAINER=$(podman run -d --rm \
        -e ACCEPT_EULA=Y \
        -e MSSQL_SA_PASSWORD='Skink!test123' \
        -p "127.0.0.1:$PORT:1433" "$IMAGE")
    echo "started mssql container $CONTAINER on :$PORT"
    # Wait for SQL Server to accept logins (log-based readiness).
    for i in $(seq 1 120); do
        if podman logs "$CONTAINER" 2>/dev/null | grep -q "SQL Server is now ready for client connections"; then
            break
        fi
        sleep 2
    done
    sleep 2
    DSN="mssql://sa:Skink!test123@127.0.0.1:$PORT/master"
fi

SKINK_HOME="$SKINK_HOME" "$SKINK_BIN" -o "$SCRIPT_DIR/.live_test_bin" "$SCRIPT_DIR/live_test.skink" || exit 1
SKINK_MSSQL_DSN="$DSN" "$SCRIPT_DIR/.live_test_bin"
