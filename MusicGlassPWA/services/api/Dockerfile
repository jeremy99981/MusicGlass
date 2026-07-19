# ── Build ─────────────────────────────────────────────────────────────────────
FROM golang:1.26-bookworm AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN GOMAXPROCS=2 CGO_ENABLED=0 GOOS=linux go build -p 1 -ldflags="-s -w" -o /server .

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /server /server

EXPOSE 8081
ENTRYPOINT ["/server"]
