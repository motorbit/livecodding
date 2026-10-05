# Task Board API. Run from backend/.
IMAGE   ?= taskapi:dev
PORT    ?= 8080
DB      ?= ./tasks.db
VOLUME  ?= taskapi-data
ARGS    ?=

.PHONY: run run-sqlite run-chaos test lint build docker-build docker-run

run: ## In-memory store, seeded on start.
	go run ./cmd/taskapi --addr=:$(PORT) $(ARGS)

run-sqlite: ## SQLite store at $(DB); data survives restarts.
	go run ./cmd/taskapi --addr=:$(PORT) --store=sqlite --db=$(DB) $(ARGS)

run-chaos: ## Challenge latency and ~15% simulated 500s on /tasks routes.
	go run ./cmd/taskapi --addr=:$(PORT) --read-latency=300ms-800ms --write-latency=100ms-300ms --failure-rate=0.15 $(ARGS)

test:
	go test -race ./...

lint:
	go vet ./...
	@out="$$(gofmt -l .)"; if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

build:
	CGO_ENABLED=0 go build -trimpath -o bin/taskapi ./cmd/taskapi

docker-build:
	docker build -t $(IMAGE) .

# Pass flags with ARGS, e.g. make docker-run ARGS=--store=sqlite (db lives on the $(VOLUME) volume).
docker-run:
	docker run --rm -p $(PORT):8080 -v $(VOLUME):/data $(IMAGE) $(ARGS)
