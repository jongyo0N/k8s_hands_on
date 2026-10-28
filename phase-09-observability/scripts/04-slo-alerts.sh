#!/usr/bin/env bash
# Phase 9 / lab 4 — SLO 번레이트 다중창 알림
# 실행: bash scripts/04-slo-alerts.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="${SCRIPT_DIR}/../manifests"
CTX="kind-k8s-mastery"; MON_NS="monitoring"; REL="kube-prometheus-stack"

echo "==> 1) SLO PrometheusRule 적용 (가용성 99.9% 목표)"
kubectl --context "$CTX" apply -f "$M/04-slo-rules.yaml"

echo "==> 2) Operator가 룰을 로드했는지 확인"
kubectl --context "$CTX" get prometheusrule -A | grep -i slo || true

cat <<EOF

==> 3) 개념: 다중창(multi-window) 번레이트
    - 에러버짓 = 1 - SLO(=0.1%). 번레이트 = 실제 에러율 / (1-SLO).
    - 빠른 창(예: 5m)+느린 창(예: 1h)을 'AND'로 묶어, 급성 폭증은 빨리 잡고
      느린 누수는 놓치지 않으면서 오탐(flapping)은 줄인다.
    - 페이지(즉시 호출)용 높은 번레이트(예: 14.4x@5m&1h) vs 티켓용 낮은 번레이트(예: 3x@6h).

    확인:
      kubectl --context ${CTX} -n ${MON_NS} port-forward svc/${REL}-prometheus 9090:9090
      # 9090 → Alerts 탭에서 SLO 알림 상태 확인
      # 에러를 유발해 번레이트를 띄우려면:
      kubectl --context ${CTX} -n phase-09 run burn --image=curlimages/curl:8.11.1 --restart=Never --rm -i \\
        --command -- sh -c 'for i in \$(seq 1 300); do curl -s demo-app:8080/error >/dev/null; done; echo done'

    [철학] 원인 기반 알림(많고 시끄러움)보다 '증상/SLO 기반'(적고 행동 가능)으로.
EOF
