#!/usr/bin/env bash
# Phase 3 — 정리: phase-03 네임스페이스(랩 리소스 전부) 삭제
# 실행: bash phase-03-services/scripts/99-cleanup.sh
#
# 클러스터 자체는 Phase 0 소유라 건드리지 않는다. 네임스페이스만 지우면 이 Phase의 모든
# Deployment/Service/Pod/EndpointSlice가 함께 사라진다.
set -euo pipefail

CTX="kind-k8s-mastery"
NS="phase-03"

if kubectl --context "$CTX" get namespace "$NS" >/dev/null 2>&1; then
  echo "==> 네임스페이스 '${NS}' 삭제 (안의 모든 리소스 포함)"
  kubectl --context "$CTX" delete namespace "$NS" --wait=true
  echo "    완료."
else
  echo "삭제할 '${NS}' 네임스페이스가 없음."
fi

echo
echo "참고: kind 클러스터 전체를 지우려면 Phase 0의 스크립트를 쓴다 ->"
echo "      bash phase-00-setup/scripts/99-cleanup.sh"
