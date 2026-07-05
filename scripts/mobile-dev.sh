#!/usr/bin/env bash
# Run a local dev server and expose it on your phone via a public URL.
#
# Usage:
#   npm run mobile
#   npm run mobile -- --hot
#   npm run mobile -- --port 3000
#
# Copy scripts/mobile-dev.sh into any Angular, React, or Node.js project.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PORT="${PORT:-}"
MODE="stable"
INSTALL_DEPS=1
TUNNEL_LOG="/tmp/mobile-dev-tunnel-$$.log"
SERVER_LOG="/tmp/mobile-dev-server-$$.log"
SERVER_PID=""
TUNNEL_PID=""

usage() {
  cat <<'EOF'
Mobile dev helper

  npm run mobile                 Stable preview (recommended for phone)
  npm run mobile -- --hot        Live reload dev server
  npm run mobile -- --port 3000  Custom port
  npm run mobile -- --no-install Skip npm install

Supported projects:
  - Angular (angular.json)
  - Vite / React (vite.config.*)
  - Create React App (react-scripts)
  - Next.js (next)
  - Generic Node.js (npm start / npm run dev)

Phone tip:
  If loca.lt asks for a tunnel password, enter your phone's public IP.
  Search "what is my ip" on your phone browser to find it.
EOF
}

log() {
  printf '\n\033[1;36m[mobile]\033[0m %s\n' "$1"
}

warn() {
  printf '\n\033[1;33m[mobile]\033[0m %s\n' "$1"
}

fail() {
  printf '\n\033[1;31m[mobile]\033[0m %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "$TUNNEL_PID" ] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    kill "$TUNNEL_PID" 2>/dev/null || true
  fi
  rm -f "$TUNNEL_LOG" "$SERVER_LOG"
}

trap cleanup EXIT INT TERM

while [ $# -gt 0 ]; do
  case "$1" in
    --hot)
      MODE="hot"
      shift
      ;;
    --stable)
      MODE="stable"
      shift
      ;;
    --port)
      PORT="${2:-}"
      [ -n "$PORT" ] || fail "Missing value for --port"
      shift 2
      ;;
    --no-install)
      INSTALL_DEPS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

command -v node >/dev/null 2>&1 || fail "Node.js is required."
command -v npm >/dev/null 2>&1 || fail "npm is required."
[ -f package.json ] || fail "Run this from a project root that contains package.json."

setup_node_compat() {
  local node_major
  node_major="$(node -p "process.versions.node.split('.')[0]")"
  if [ "$node_major" -ge 17 ]; then
    if [ -z "${NODE_OPTIONS:-}" ]; then
      export NODE_OPTIONS="--openssl-legacy-provider"
      warn "Node $node_major detected. Enabled NODE_OPTIONS=--openssl-legacy-provider for older webpack builds."
    fi
  fi
}

detect_project() {
  if [ -f angular.json ]; then
    echo "angular"
  elif [ -f vite.config.ts ] || [ -f vite.config.js ] || [ -f vite.config.mjs ]; then
    echo "vite"
  elif node -e "const p=require('./package.json'); process.exit(p.dependencies?.['react-scripts'] || p.devDependencies?.['react-scripts'] ? 0 : 1)" 2>/dev/null; then
    echo "cra"
  elif node -e "const p=require('./package.json'); process.exit(p.dependencies?.next || p.devDependencies?.next ? 0 : 1)" 2>/dev/null; then
    echo "next"
  else
    echo "node"
  fi
}

default_port() {
  case "$1" in
    angular) echo "4200" ;;
    vite) echo "5173" ;;
    cra|next) echo "3000" ;;
    *) echo "8080" ;;
  esac
}

angular_dist_path() {
  if command -v node >/dev/null 2>&1; then
    node <<'NODE'
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('angular.json', 'utf8'));
const projectName = Object.keys(config.projects || {})[0];
const outputPath = config.projects?.[projectName]?.architect?.build?.options?.outputPath;
if (!outputPath) process.exit(1);
process.stdout.write(outputPath);
NODE
    return
  fi

  grep -o '"outputPath"[[:space:]]*:[[:space:]]*"[^"]*"' angular.json | head -1 | sed 's/.*"\([^"]*\)".*/\1/'
}

wait_for_url() {
  local url="$1"
  local i
  for i in $(seq 1 60); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_tunnel_url() {
  local i url
  for i in $(seq 1 30); do
    url="$(grep -o 'https://[a-z0-9-]*\.loca\.lt' "$TUNNEL_LOG" 2>/dev/null | head -1 || true)"
    if [ -n "$url" ]; then
      echo "$url"
      return 0
    fi
    sleep 1
  done
  return 1
}

start_tunnel() {
  : > "$TUNNEL_LOG"
  npx --yes localtunnel --port "$PORT" --local-host 127.0.0.1 >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!
}

start_angular_stable() {
  local dist_path
  dist_path="$(angular_dist_path)" || fail "Could not read Angular outputPath from angular.json."

  log "Building Angular app for a stable mobile preview..."
  if npm run | grep -q '^  build'; then
    npm run build -- --configuration=production
  else
    npx ng build --configuration=production
  fi

  [ -d "$dist_path" ] || fail "Build output not found at $dist_path"
  PORT="${PORT:-8080}"

  log "Serving static build on port $PORT..."
  npx --yes http-server "$dist_path" -p "$PORT" -a 127.0.0.1 --cors -c-1 >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
}

start_angular_hot() {
  PORT="${PORT:-4200}"
  log "Starting Angular dev server on port $PORT..."
  if npm run | grep -q '^  start'; then
    npm run start -- --host 0.0.0.0 --port "$PORT" --disable-host-check >"$SERVER_LOG" 2>&1 &
  else
    npx ng serve --host 0.0.0.0 --port "$PORT" --disable-host-check >"$SERVER_LOG" 2>&1 &
  fi
  SERVER_PID=$!
}

start_vite_hot() {
  PORT="${PORT:-5173}"
  log "Starting Vite dev server on port $PORT..."
  npm run dev -- --host 0.0.0.0 --port "$PORT" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
}

start_vite_stable() {
  PORT="${PORT:-4173}"
  log "Building Vite app for a stable mobile preview..."
  npm run build
  log "Serving Vite preview on port $PORT..."
  npm run preview -- --host 127.0.0.1 --port "$PORT" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
}

start_cra_hot() {
  PORT="${PORT:-3000}"
  log "Starting Create React App dev server on port $PORT..."
  HOST=0.0.0.0 PORT="$PORT" npm start >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
}

start_next_hot() {
  PORT="${PORT:-3000}"
  log "Starting Next.js dev server on port $PORT..."
  npm run dev -- -H 0.0.0.0 -p "$PORT" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
}

start_node_generic() {
  PORT="${PORT:-8080}"
  if npm run | grep -q '^  dev'; then
    log "Starting npm run dev on port $PORT..."
    npm run dev >"$SERVER_LOG" 2>&1 &
  elif npm run | grep -q '^  start'; then
    log "Starting npm start..."
    PORT="$PORT" npm start >"$SERVER_LOG" 2>&1 &
  else
    fail "Could not find a start/dev script in package.json."
  fi
  SERVER_PID=$!
}

if [ "$INSTALL_DEPS" -eq 1 ] && [ ! -d node_modules ]; then
  log "Installing dependencies..."
  npm install --legacy-peer-deps
fi

setup_node_compat

PROJECT_TYPE="$(detect_project)"
[ -z "$PORT" ] && PORT="$(default_port "$PROJECT_TYPE")"

log "Detected project: $PROJECT_TYPE"
log "Mode: $MODE"
log "Port: $PORT"

case "$PROJECT_TYPE" in
  angular)
    if [ "$MODE" = "hot" ]; then
      start_angular_hot
    else
      start_angular_stable
    fi
    ;;
  vite)
    if [ "$MODE" = "hot" ]; then
      start_vite_hot
    else
      start_vite_stable
    fi
    ;;
  cra)
    if [ "$MODE" = "stable" ]; then
      warn "CRA stable mode uses the dev server. Use --hot explicitly if needed."
    fi
    start_cra_hot
    ;;
  next)
    if [ "$MODE" = "stable" ]; then
      warn "Next.js stable mode uses the dev server. Use production deploy for a static preview."
    fi
    start_next_hot
    ;;
  node)
    start_node_generic
    ;;
  *)
    fail "Unsupported project type."
    ;;
esac

log "Waiting for local server..."
wait_for_url "http://127.0.0.1:$PORT/" || {
  tail -20 "$SERVER_LOG" >&2 || true
  fail "Local server did not start on port $PORT."
}

log "Creating mobile tunnel..."
start_tunnel
MOBILE_URL="$(wait_for_tunnel_url)" || {
  tail -20 "$TUNNEL_LOG" >&2 || true
  fail "Could not create a public mobile URL."
}

cat <<EOF

============================================================
  Mobile preview is ready
============================================================

  Local:   http://127.0.0.1:$PORT/
  Mobile:  $MOBILE_URL

  Open the Mobile URL on your phone.

  If loca.lt asks for a password:
    1. On your phone, search "what is my ip"
    2. Enter that IP on the tunnel page
    3. Tap Continue

  Press Ctrl+C to stop.
============================================================

EOF

wait "$SERVER_PID"
