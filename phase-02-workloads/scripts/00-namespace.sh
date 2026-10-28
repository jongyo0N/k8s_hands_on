#!/usr/bin/env bash
# Phase 2 / 준비 — 모든 랩이 공유하는 네임스페이스 phase-02 생성
# 실행: bash phase-02-workloads/scripts/00-namespace.sh
# 전제: Phase 0의 kind 클러스터가 떠 있고 context가 kind-k8s-mastery 이다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
MANIFESTS="${SCRIPT_DIR}/../manifests"

echo "==> context 확인"
kubectl --context "${CTX}" cluster-info >/dev/null
echo "    ok: ${CTX}"

echo
echo "==> 네임스페이스 phase-02 생성 (이미 있으면 그대로 둠)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-namespace.yaml"

echo
echo "다음: bash phase-02-workloads/scripts/01-startup-probe.sh"
