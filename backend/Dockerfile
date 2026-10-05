FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/taskapi ./cmd/taskapi \
    && mkdir -p /out/data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/taskapi /taskapi
# Writable by the nonroot user (uid 65532); mount a volume here for --store=sqlite.
COPY --from=build --chown=65532:65532 /out/data /data
ENV ADDR=:8080 \
    DB=/data/tasks.db
VOLUME ["/data"]
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/taskapi"]
