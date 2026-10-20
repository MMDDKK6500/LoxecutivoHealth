#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/home/ubuntu/loxecutivo"
CORE="$ROOT/LoxecutivoCore"
AUTH="$ROOT/LoxecutivoAuth"
EXPORT="$ROOT/LoxecutivoExport"
HEALTH="$ROOT/LoxecutivoHealth"
FRONTEND="$ROOT/LoxecutivoFrontend"
WEBROOT="/var/www/loxecutivo-frontend"

BRANCH="main"
AUTH_PM2_TARGET="2"
EXPORT_PM2_TARGET="loxecutivo-export"
HEALTH_PM2_TARGET="loxecutivo-health"
HEALTH_SERVICES_URL="http://127.0.0.1:8084/services"
CORE_SERVICE="loxecutivo-core"

pull_repo() {
  git -C "$1" pull --ff-only origin "$BRANCH"
}

require_env_file() {
  local project="$1"
  if [[ ! -f "$project/.env" ]]; then
    echo "Missing $project/.env; configure it from .env.example first." >&2
    exit 1
  fi
}

start_or_restart_pm2() {
  local name="$1"
  local directory="$2"
  local entrypoint="$3"

  if pm2 describe "$name" >/dev/null 2>&1; then
    pm2 restart "$name" --update-env
  else
    pm2 start "$entrypoint" --name "$name" --cwd "$directory" --time
  fi
}

echo "Pulling repositories..."
pull_repo "$CORE"
pull_repo "$AUTH"
pull_repo "$EXPORT"
pull_repo "$HEALTH"
pull_repo "$FRONTEND"

echo "Checking environment files..."
require_env_file "$AUTH"
require_env_file "$EXPORT"
require_env_file "$HEALTH"

echo "Installing Node dependencies..."
(cd "$AUTH" && npm ci)
(cd "$EXPORT" && npm ci)
(cd "$HEALTH" && npm ci)
(cd "$FRONTEND" && npm ci)

echo "Building Spring Boot Core..."
(cd "$CORE" && sh ./mvnw clean -DskipTests package)

CORE_JAR="$(find "$CORE/target" -maxdepth 1 -type f -name '*.jar' ! -name '*-plain.jar' -print -quit)"
if [[ -z "$CORE_JAR" ]]; then
  echo "Could not find the packaged Spring Boot JAR in $CORE/target." >&2
  exit 1
fi
install -m 0644 "$CORE_JAR" "$ROOT/loxecutivo-core.jar"

echo "Building React frontend..."
(cd "$FRONTEND" && npm run build)

echo "Restarting Auth service..."
pm2 restart "$AUTH_PM2_TARGET" --update-env

echo "Restarting Core service..."
sudo systemctl restart "$CORE_SERVICE"
sudo systemctl is-active --quiet "$CORE_SERVICE"

echo "Starting or restarting Export service..."
start_or_restart_pm2 "$EXPORT_PM2_TARGET" "$EXPORT" "$EXPORT/src/index.js"

echo "Starting or restarting Health service..."
start_or_restart_pm2 "$HEALTH_PM2_TARGET" "$HEALTH" "$HEALTH/src/index.js"

pm2 save

echo "Checking all microservices through Health service..."
HEALTH_REPORT="$(mktemp)"
trap 'rm -f "$HEALTH_REPORT"' EXIT
HEALTH_READY=false
for attempt in {1..30}; do
  if HEALTH_HTTP_STATUS="$(curl --silent --output "$HEALTH_REPORT" --write-out '%{http_code}' "$HEALTH_SERVICES_URL")" \
    && [[ "$HEALTH_HTTP_STATUS" == "200" ]]; then
    cat "$HEALTH_REPORT"
    HEALTH_READY=true
    break
  fi
  echo "Services are still starting (attempt $attempt/30)..."
  sleep 2
done
if [[ "$HEALTH_READY" != true ]]; then
  echo "One or more microservices did not become healthy. Deployment stopped before replacing the frontend." >&2
  cat "$HEALTH_REPORT" >&2 || true
  exit 1
fi
echo

echo "Deploying frontend files..."
sudo install -d -o www-data -g www-data "$WEBROOT"
sudo rsync -a --delete --chown=www-data:www-data "$FRONTEND/dist/" "$WEBROOT/"

echo "Deployment completed successfully."
