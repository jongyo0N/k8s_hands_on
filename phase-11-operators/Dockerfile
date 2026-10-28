# 멀티스테이지 빌드: 빌드 스테이지에서 정적 바이너리를 만들고,
# 최종 이미지는 distroless(nonroot)로 — 셸도 패키지 매니저도 없는 최소 공격면.
FROM golang:1.24 AS builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace
# 의존성 캐시 레이어: go.mod/go.sum 만 먼저 복사해 받아 둔다.
COPY go.mod go.mod
COPY go.sum go.sum
RUN go mod download

# 소스 복사 후 빌드.
COPY cmd/ cmd/
COPY api/ api/
COPY internal/ internal/

# CGO 비활성 + 정적 링크 → distroless 에서 바로 뜬다.
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} \
    go build -a -o manager cmd/main.go

FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /workspace/manager .
USER 65532:65532

ENTRYPOINT ["/manager"]
