#!/usr/bin/env bash
# Starts the Task API in Docker on Colima, asking which configuration to run.
#
#   ./scripts/start.sh            # interactive
#   PORT=$(./scripts/start.sh)    # stdout is only the port; prompts and logs go to stderr
#
# Any option can be preset (skips its prompt): STORE, SEED, CHAOS, LOG_FORMAT, PORT, REBUILD=1.
# Example: STORE=sqlite SEED=empty CHAOS=off LOG_FORMAT=text PORT=8080 ./scripts/start.sh
set -euo pipefail

IMAGE="${IMAGE:-taskapi:dev}"
CONTAINER="${CONTAINER:-taskapi}"
VOLUME="${VOLUME:-taskapi-data}"
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

# ask VAR "Question" default option1 option2 ...  (keeps a preset VAR value if it's valid)
ask() {
  local var="$1" question="$2" default="$3"
  shift 3
  local options=("$@") answer="${!var:-}"
  while true; do
    if [[ -z "$answer" ]]; then
      read -r -p "$question [$(IFS=/; echo "${options[*]}")] (default: $default): " answer </dev/tty
      answer="${answer:-$default}"
    fi
    local o
    for o in "${options[@]}"; do
      if [[ "$answer" == "$o" ]]; then
        printf -v "$var" '%s' "$answer"
        return
      fi
    done
    log "  '$answer' is not one of: ${options[*]}"
    answer=""
  done
}

port_in_use() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

# 1. Colima + Docker
command -v colima >/dev/null || die "colima is not installed (brew install colima docker)"
command -v docker >/dev/null || die "docker CLI is not installed (brew install docker)"
if colima status >/dev/null 2>&1; then
  log "✓ colima is running"
else
  log "… colima is not running, starting it"
  colima start >&2
fi
docker info >/dev/null 2>&1 || die "docker can't reach the daemon (check: docker context use colima)"

# 2. Configuration
ask STORE      "Store"                       memory memory sqlite
ask SEED       "Initial data"                filled filled empty
ask CHAOS      "Chaos (latency + ~15% 500s)" off    off on
ask LOG_FORMAT "Log format"                  text   text json

if [[ -z "${PORT:-}" ]]; then
  read -r -p "Port (default: 8080): " PORT </dev/tty
  PORT="${PORT:-8080}"
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  die "invalid port: $PORT"
fi

# 3. Replace a previous container (frees its port), then find a free port
if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
  log "… removing previous '$CONTAINER' container"
  docker rm -f "$CONTAINER" >/dev/null
  sleep 1
fi
requested="$PORT"
while port_in_use "$PORT"; do PORT=$((PORT + 1)); done
if [[ "$PORT" != "$requested" ]]; then
  log "! port $requested is busy, using $PORT"
fi

# 4. Image (built when missing, or always with REBUILD=1)
if [[ "${REBUILD:-}" == "1" ]] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  log "… building $IMAGE"
  docker build -q -t "$IMAGE" "$BACKEND_DIR" >&2
fi

# 5. Run
args=(--store="$STORE" --seed="$SEED" --log-format="$LOG_FORMAT")
if [[ "$CHAOS" == "on" ]]; then
  args+=(--read-latency=300ms-800ms --write-latency=100ms-300ms --failure-rate=0.15)
fi
run_opts=(-d --name "$CONTAINER" -p "$PORT:8080")
if [[ "$STORE" == "sqlite" ]]; then
  run_opts+=(-v "$VOLUME:/data")
fi

docker run "${run_opts[@]}" "$IMAGE" "${args[@]}" >/dev/null

healthy=false
for _ in $(seq 1 30); do
  if curl -fsS "http://localhost:$PORT/healthz" >/dev/null 2>&1; then
    healthy=true
    break
  fi
  sleep 0.5
done
if [[ "$healthy" != true ]]; then
  docker logs "$CONTAINER" >&2 || true
  die "server did not become healthy on port $PORT"
fi

log ""
log "✓ Task API running: http://localhost:$PORT  (store=$STORE seed=$SEED chaos=$CHAOS log=$LOG_FORMAT)"
log "  logs: docker logs -f $CONTAINER    stop: docker rm -f $CONTAINER"
echo "$PORT"
