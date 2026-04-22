# syntax=docker/dockerfile:1.7
FROM golang:1.22-bookworm AS builder

WORKDIR /build

ENV GONOSUMCHECK=* \
    GOFLAGS=-mod=mod \
    GOPROXY=direct

COPY app/dashboard/go.mod go.mod
COPY app/dashboard/main.go main.go

RUN go mod tidy

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" \
    -o dashboard .

FROM scratch

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /build/dashboard /dashboard

EXPOSE 8081

USER 65532:65532

ENTRYPOINT ["/dashboard"]