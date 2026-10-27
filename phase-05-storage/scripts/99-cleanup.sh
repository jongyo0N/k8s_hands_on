#!/usr/bin/env bash
# Phase 5 — 정리 (클러스터는 남기고 Phase 5 리소스만 제거)
# 실행: bash phase-05-storage/scripts/99-cleanup.sh
#
# 정리는 "이미 없음"에도 관대해야 하므로 각 단계를 || true 로 감싼다.
set -uo pipefail

CTX="kind-k8s-mastery"
NS="phase-05"
CNPG_NS="cnpg-system"
CNPG_VERSION="1.30.1"
CNPG_MANIFEST="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-${CNPG_VERSION}.yaml"

echo "==> 1) CloudNativePG Cluster 먼저 삭제 (operator가 Pod/PVC 정리하도록)"
kubectl --context "${CTX}" -n "${NS}" delete cluster pg-sample --ignore-not-found --timeout=90s || true

echo
echo "==> 2) lab 3에서 cordon된 노드 되돌리기 (모든 노드 uncordon — 이미 정상이면 무해)"
for n in $(kubectl --context "${CTX}" get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  kubectl --context "${CTX}" uncordon "${n}" >/dev/null 2>&1 || true
done
echo "    완료."

echo
echo "==> 3) namespace '${NS}' 삭제 (안의 PVC 삭제 → local-path PV는 reclaim=Delete로 자동 회수)"
kubectl --context "${CTX}" delete namespace "${NS}" --ignore-not-found --timeout=120s || true

echo
echo "==> 4) lab 1에서 만든 커스텀 StorageClass 삭제"
kubectl --context "${CTX}" delete storageclass phase05-local-immediate phase05-local-wffc \
  --ignore-not-found || true

echo
echo "==> 5) (선택) CloudNativePG operator 제거 — CRD까지 지우므로 주의"
echo "    operator/CRD를 남겨두려면 이 단계를 건너뛰어도 된다."
read -r -p "    operator를 제거할까? [y/N] " ans || ans="N"
case "${ans}" in
  y|Y)
    kubectl --context "${CTX}" delete -f "${CNPG_MANIFEST}" --ignore-not-found || true
    kubectl --context "${CTX}" delete namespace "${CNPG_NS}" --ignore-not-found || true
    echo "    operator 제거 완료."
    ;;
  *)
    echo "    operator 유지."
    ;;
esac

echo
echo "==> 6) 남은 PV 확인 (비어 있어야 정상)"
kubectl --context "${CTX}" get pv 2>/dev/null | grep -Ei 'phase05|pg-sample|rwo|trace|immediate|wffc' \
  || echo "    Phase 5 관련 PV 없음."

echo
echo "정리 완료."
