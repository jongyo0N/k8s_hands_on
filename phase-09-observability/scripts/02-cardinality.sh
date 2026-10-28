#!/usr/bin/env bash
# Phase 9 / lab 2 — (관찰) cardinality 폭발 재현 → 회복
# 실행: bash scripts/02-cardinality.sh
set -uo pipefail

CTX="kind-k8s-mastery"; NS="phase-09"; MON_NS="monitoring"; REL="kube-prometheus-stack"

series() {
  # Prometheus HTTP API로 현재 head 시계열 수를 질의(port-forward 필요 없이 Pod 내부에서).
  kubectl --context "$CTX" -n "$MON_NS" exec sts/prometheus-"$REL"-prometheus -c prometheus -- \
    sh -c 'wget -qO- "http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series" 2>/dev/null' 2>/dev/null \
    | grep -o '"value":\[[^]]*\]' | head -1
}

echo "==> 0) 현재 시계열 수(before)"; series || echo "   (Prometheus Pod 이름/경로 확인 필요)"

echo "==> 1) HIGH_CARDINALITY 켜기 — 요청마다 고유 user_id 라벨 생성"
kubectl --context "$CTX" -n "$NS" set env deploy/demo-app HIGH_CARDINALITY=true
kubectl --context "$CTX" -n "$NS" rollout status deploy/demo-app --timeout=60s

echo "==> 2) 부하 생성(고유 요청 다수) — 각 요청이 새 시계열을 만든다"
kubectl --context "$CTX" -n "$NS" run load --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet \
  --command -- sh -c 'for i in $(seq 1 800); do curl -s demo-app:8080/ >/dev/null; curl -s demo-app:8080/slow >/dev/null; curl -s demo-app:8080/error >/dev/null; done; echo done' 2>/dev/null || true

echo "==> 3) 스크랩 반영 대기 후 시계열 수(after) — 급증 확인"
sleep 20; series || true
echo "    참고: topk로 범인 메트릭 찾기 —"
echo "      topk(10, count by (__name__)({__name__=~\".+\"}))"

echo
echo "==> 4) 회복: 라벨 제거(HIGH_CARDINALITY=false)"
kubectl --context "$CTX" -n "$NS" set env deploy/demo-app HIGH_CARDINALITY=false
kubectl --context "$CTX" -n "$NS" rollout status deploy/demo-app --timeout=60s
cat <<'EOF'
    주의: 새 요청은 더 이상 고유 라벨을 안 만들지만, 이미 생긴 시계열은
    retention(기본 15일) 또는 그 시계열이 stale 될 때까지 TSDB에 남는다.
    → "일단 들어간 cardinality는 당장 사라지지 않는다"가 운영 교훈.
    예방: 고유값(user_id/email/uuid)을 라벨로 쓰지 말 것. sampleLimit/relabel로 가드레일.
EOF
