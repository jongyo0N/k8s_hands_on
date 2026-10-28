#!/usr/bin/env bash
# Phase 9 / lab 3 — OTel Collector로 trace/log 상관
# 실행: bash scripts/03-otel-correlation.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="${SCRIPT_DIR}/../manifests"
CTX="kind-k8s-mastery"; NS="phase-09"

echo "==> 1) OTel Collector 배포"
kubectl --context "$CTX" apply -f "$M/03-otel-collector.yaml"
kubectl --context "$CTX" -n "$NS" rollout status deploy/otel-collector --timeout=120s 2>/dev/null \
  || kubectl --context "$CTX" -n "$NS" rollout status daemonset/otel-collector --timeout=120s 2>/dev/null || true

echo "==> 2) 앱에 OTLP 엔드포인트 주입 (요청마다 trace+log 전송)"
# demo-app은 OTLP/HTTP(JSON)로 /v1/traces, /v1/logs 에 POST한다. Collector의 OTLP http 수신(4318)로.
kubectl --context "$CTX" -n "$NS" set env deploy/demo-app \
  OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.${NS}:4318" \
  OTEL_SERVICE_NAME="demo-app"
kubectl --context "$CTX" -n "$NS" rollout status deploy/demo-app --timeout=60s

echo "==> 3) 트래픽 생성"
kubectl --context "$CTX" -n "$NS" run otelload --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet \
  --command -- sh -c 'for i in $(seq 1 30); do curl -s demo-app:8080/ >/dev/null; curl -s demo-app:8080/slow >/dev/null; curl -s demo-app:8080/error >/dev/null; done; echo done' 2>/dev/null || true

echo "==> 4) 상관 관찰"
echo "    앱 로그(구조화, trace_id 포함):"
kubectl --context "$CTX" -n "$NS" logs deploy/demo-app --tail=5 | grep -o '"trace_id":"[^"]*"' | head -3 || true
echo "    Collector 로그(수신/내보내기 파이프라인):"
kubectl --context "$CTX" -n "$NS" logs -l app=otel-collector --tail=10 2>/dev/null | tail -10 || true
cat <<'EOF'

    핵심: 로그의 trace_id ↔ trace의 traceId가 같다. 백엔드(Tempo/Jaeger+Loki)에서
    "이 느린 요청"의 로그→트레이스→스팬을 한 번에 넘나든다. (Collector가 수집 표준 허브)
EOF
