# syntax=docker/dockerfile:1

FROM oven/bun:latest AS builder

WORKDIR /build
COPY web/package.json web/bun.lock ./
RUN --mount=type=cache,target=/root/.bun bun install
COPY ./web .
COPY ./VERSION .
RUN DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat VERSION) bun run build

FROM golang:1.26.1-alpine@sha256:2389ebfa5b7f43eeafbd6be0c3700cc46690ef842ad962f6c5bd6be49ed82039 AS builder2
ENV GO111MODULE=on CGO_ENABLED=0

ARG TARGETOS
ARG TARGETARCH
ENV GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64}
ENV GOEXPERIMENT=greenteagc

WORKDIR /build

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY main.go ./
COPY common/ constant/ controller/ dto/ i18n/ logger/ middleware/ model/ oauth/ pkg/ relay/ router/ service/ setting/ types/ ./
COPY --from=builder /build/dist ./web/dist
RUN go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api

FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata wget \
    && adduser -D -u 1000 appuser

COPY --from=builder2 /build/new-api /
EXPOSE 3000
WORKDIR /data
USER appuser
ENTRYPOINT ["/new-api"]
