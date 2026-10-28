#!/usr/bin/env bash
# Phase 9 — 정리
# 실행: bash scripts/99-cleanup.sh
set -uo pipefail

CTX="kind-k8s-mastery"; MON_NS="monitoring"; REL="kube-prometheus-stack"

echo "==> 샘플 앱/네임스페이스 삭제"
kubectl --context "$CTX" delete ns phase-09 --ignore-not-found

echo "==> 모니터링 스택 제거"
helm --kube-context "$CTX" uninstall "$REL" -n "$MON_NS" 2>/dev/null || true
kubectl --context "$CTX" delete ns "$MON_NS" --ignore-not-found

echo "    완료. (CRD는 helm이 남겨둘 수 있다 — 필요시 kubectl get crd | grep monitoring 로 확인)"
