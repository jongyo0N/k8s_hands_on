#!/usr/bin/env bash
# Phase 7 — 실습 리소스 정리
# 실행: bash phase-07-scheduling/scripts/99-cleanup.sh
#
# 기본: phase-07 네임스페이스 삭제 + (혹시 남은) cordon 노드 해제.
# 옵션(기본은 보존 — 이후 재실습에 재사용 가능):
#   REMOVE_METRICS_SERVER=1  → metrics-server 제거
#   REMOVE_KEDA=1            → KEDA(helm) 제거
set -euo pipefail

CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
NS="phase-07"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-v0.9.0}"

echo "==> 1) 혹시 drain 후 cordon 상태로 남은 노드가 있으면 전부 해제"
for node in $(kubectl --context "${CTX}" get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  kubectl --context "${CTX}" uncordon "${node}" >/dev/null 2>&1 || true
done
echo "    완료."

echo
echo "==> 2) 부하 생성기 / 네임스페이스 삭제 (${NS} 안의 모든 랩 리소스 포함)"
kubectl --context "${CTX}" -n "${NS}" delete pod load-generator --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "${CTX}" delete namespace "${NS}" --ignore-not-found
echo "    완료."

if [ "${REMOVE_METRICS_SERVER:-0}" = "1" ]; then
  echo
  echo "==> (옵션) metrics-server 제거"
  kubectl --context "${CTX}" delete -f \
    "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml" \
    --ignore-not-found || true
else
  echo
  echo "    (metrics-server는 보존. 제거하려면: REMOVE_METRICS_SERVER=1 bash .../99-cleanup.sh)"
fi

if [ "${REMOVE_KEDA:-0}" = "1" ]; then
  echo
  echo "==> (옵션) KEDA 제거"
  if command -v helm >/dev/null 2>&1; then
    helm uninstall keda --kube-context "${CTX}" --namespace keda || true
  fi
  kubectl --context "${CTX}" delete namespace keda --ignore-not-found || true
else
  echo "    (KEDA는 보존. 제거하려면: REMOVE_KEDA=1 bash .../99-cleanup.sh)"
fi

echo
echo "정리 끝. 클러스터 자체를 지우려면 Phase 0: bash phase-00-setup/scripts/99-cleanup.sh"
