#!/usr/bin/env bash
# Phase 0 — 클러스터 삭제
# 실행: bash phase-00-setup/scripts/99-cleanup.sh
set -euo pipefail

CLUSTER_NAME="k8s-mastery"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> kind 클러스터 '${CLUSTER_NAME}' 삭제"
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "    완료."
else
  echo "삭제할 '${CLUSTER_NAME}' 클러스터가 없음."
fi
