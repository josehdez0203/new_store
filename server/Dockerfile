# syntax=docker/dockerfile:1

ARG GO_VERSION=1.26.5
FROM golang:${GO_VERSION}-alpine AS build

WORKDIR /src

RUN apk add --no-cache ca-certificates

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build \
        -trimpath -buildvcs=false -ldflags="-s -w" \
        -o /out/api ./cmd/api \
    && CGO_ENABLED=0 GOOS=linux go build \
        -trimpath -buildvcs=false -ldflags="-s -w" \
        -o /out/seed ./cmd/seed

FROM alpine:3.22

RUN apk add --no-cache ca-certificates tzdata wget \
    && addgroup -S app \
    && adduser -S -G app app

WORKDIR /app

COPY --from=build /out/api /app/api
COPY --from=build /out/seed /app/seed

RUN mkdir -p /data/downloads/products \
    && chown -R app:app /data

ENV APP_ENV=production \
    API_PORT=8081 \
    DOWNLOADS_DIR=/data/downloads \
    TZ=UTC

USER app

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8081/ready || exit 1

ENTRYPOINT ["/app/api"]
