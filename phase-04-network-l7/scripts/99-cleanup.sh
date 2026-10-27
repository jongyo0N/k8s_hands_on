#!/usr/bin/env bash
# Phase 4 — 클러스터 삭제
# 실행: bash phase-04-network-l7/scripts/99-cleanup.sh
set -euo pipefail

CLUSTER_NAME="k8s-l7"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> kind 클러스터 '${CLUSTER_NAME}' 삭제"
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "    완료. (Gateway API CRD/Cilium은 클러스터와 함께 사라진다.)"
else
  echo "삭제할 '${CLUSTER_NAME}' 클러스터가 없음."
fi
