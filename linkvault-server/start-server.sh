#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

CONFIG_FILE="$SCRIPT_DIR/server.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

set -a
. "$CONFIG_FILE"
set +a

: "${SPRING_PROFILES_ACTIVE:=dev}"
: "${LINKVAULT_SERVER_PORT:=8080}"
: "${LINKVAULT_POSTGRES_HOST_PORT:=5432}"
: "${LINKVAULT_REDIS_HOST_PORT:=6379}"
: "${LINKVAULT_MINIO_API_HOST_PORT:=9000}"
: "${LINKVAULT_MINIO_CONSOLE_HOST_PORT:=9001}"
: "${LINKVAULT_POSTGRES_DB:=linkvault}"
: "${LINKVAULT_POSTGRES_USER:=linkvault}"
: "${LINKVAULT_POSTGRES_PASSWORD:=linkvault}"
: "${LINKVAULT_MINIO_ACCESS_KEY:=linkvault}"
: "${LINKVAULT_MINIO_SECRET_KEY:=linkvault-secret}"
: "${LINKVAULT_MINIO_BUCKET:=linkvault}"

export SPRING_PROFILES_ACTIVE
export LINKVAULT_SERVER_PORT
export LINKVAULT_DATASOURCE_URL="jdbc:postgresql://localhost:${LINKVAULT_POSTGRES_HOST_PORT}/${LINKVAULT_POSTGRES_DB}"
export LINKVAULT_DATASOURCE_USERNAME="$LINKVAULT_POSTGRES_USER"
export LINKVAULT_DATASOURCE_PASSWORD="$LINKVAULT_POSTGRES_PASSWORD"
export LINKVAULT_REDIS_HOST=localhost
export LINKVAULT_REDIS_PORT="$LINKVAULT_REDIS_HOST_PORT"
export LINKVAULT_MINIO_ENDPOINT="http://localhost:${LINKVAULT_MINIO_API_HOST_PORT}"
export LINKVAULT_MINIO_PUBLIC_ENDPOINT="http://localhost:${LINKVAULT_MINIO_API_HOST_PORT}"
export LINKVAULT_MINIO_INITIALIZE_BUCKET=true

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found in PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose is required but is not available through docker compose." >&2
  exit 1
fi

if ! command -v mvn >/dev/null 2>&1; then
  echo "Maven is required but was not found in PATH." >&2
  exit 1
fi

echo "Starting LinkVault Docker dependencies..."
docker compose --env-file "$CONFIG_FILE" -f infra/docker/docker-compose.yml up -d postgres redis minio minio-init

echo "Starting LinkVault API on http://localhost:${LINKVAULT_SERVER_PORT}/api/v1"
exec mvn spring-boot:run
