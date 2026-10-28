#!/usr/bin/env bash
# Phase 9 / lab 1 — kube-prometheus-stack 설치 + demo-app 연결 + RED PromQL
# 실행: bash scripts/01-prometheus-stack.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="${SCRIPT_DIR}/../manifests"
CTX="kind-k8s-mastery"
REL="kube-prometheus-stack"   # ★ ServiceMonitor의 release 라벨과 반드시 동일
MON_NS="monitoring"

echo "==> 1) helm 저장소"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "==> 2) kube-prometheus-stack 설치 (네임스페이스 ${MON_NS}, 릴리스 ${REL})"
echo "    ⚠️ 버전 고정 권장: helm search repo prometheus-community/kube-prometheus-stack --versions"
helm --kube-context "$CTX" upgrade --install "$REL" prometheus-community/kube-prometheus-stack \
  -n "$MON_NS" --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=true \
  --wait --timeout 10m
  # 최신 확인 후 '--version <x.y.z>' 를 붙여 재현성을 고정하라.

echo "==> 3) 샘플 앱 + ServiceMonitor + 대시보드"
kubectl --context "$CTX" apply -f "$M/00-namespace.yaml"
kubectl --context "$CTX" apply -f "$M/01-demo-app.yaml"
kubectl --context "$CTX" apply -f "$M/01-servicemonitor.yaml"
kubectl --context "$CTX" apply -f "$M/01-grafana-dashboard.yaml" 2>/dev/null || true
kubectl --context "$CTX" -n phase-09 rollout status deploy/demo-app --timeout=120s

cat <<EOF

==> 4) 확인
    # Prometheus UI (Targets에서 demo-app이 UP인지 — 아니면 release 라벨 불일치):
    kubectl --context ${CTX} -n ${MON_NS} port-forward svc/${REL}-prometheus 9090:9090
    # Grafana (admin 비번):
    kubectl --context ${CTX} -n ${MON_NS} get secret ${REL}-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
    kubectl --context ${CTX} -n ${MON_NS} port-forward svc/${REL}-grafana 3000:80

    [RED PromQL — 9090에서]
      Rate:     sum(rate(http_requests_total[5m])) by (path)
      Errors:   sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
      Duration: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le,path))
EOF
