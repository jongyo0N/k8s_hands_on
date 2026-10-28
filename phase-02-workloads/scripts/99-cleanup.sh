#!/usr/bin/env bash
# Phase 2 — 전체 정리 (네임스페이스 phase-02 삭제 = 안의 모든 리소스 일괄 삭제)
# 실행: bash phase-02-workloads/scripts/99-cleanup.sh
set -euo pipefail

CTX="kind-k8s-mastery"
NS="phase-02"

if kubectl --context "${CTX}" get namespace "${NS}" >/dev/null 2>&1; then
  echo "==> 네임스페이스 ${NS} 삭제 (Pod/Deployment/StatefulSet/Job/Service/PVC 모두 포함)"
  kubectl --context "${CTX}" delete namespace "${NS}"
  echo "    완료. (PVC가 지워지면 local-path PV도 함께 회수된다 — reclaimPolicy=Delete)"
else
  echo "삭제할 네임스페이스 ${NS} 가 없음."
fi
