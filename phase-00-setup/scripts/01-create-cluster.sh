#!/usr/bin/env bash
# Phase 0 / lab 1 — 멀티노드 클러스터 생성 + 노드 라벨링
# 실행: bash phase-00-setup/scripts/01-create-cluster.sh
# 옵션: KIND_IMAGE=kindest/node:v1.33.0 bash .../01-create-cluster.sh  (노드 이미지/버전 고정)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
CONFIG="${SCRIPT_DIR}/../kind-config.yaml"

echo "==> kind 클러스터 '${CLUSTER_NAME}' 생성 (control-plane 1 + worker 3)"
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "    이미 존재함. 새로 만들려면 먼저 99-cleanup.sh 실행."
else
  kind create cluster --config "${CONFIG}" ${KIND_IMAGE:+--image "${KIND_IMAGE}"}
fi

echo
echo "==> 모든 노드가 Ready 될 때까지 대기"
kubectl --context "${CTX}" wait --for=condition=Ready nodes --all --timeout=120s

echo
echo "==> 관리자 경로로 zone 라벨 부여 (멀티 AZ 흉내 — Phase 5/7 topology spread용)"
echo "    kind-config의 node-tier와 달리, 예약 라벨 topology.kubernetes.io/zone은"
echo "    API server를 통한 관리자 권한으로만 붙일 수 있다 (NodeRestriction 우회)."
zones=(zone-a zone-b zone-a)
i=0
for node in $(kubectl --context "${CTX}" get nodes \
                -l '!node-role.kubernetes.io/control-plane' \
                -o jsonpath='{.items[*].metadata.name}'); do
  kubectl --context "${CTX}" label node "${node}" \
    "topology.kubernetes.io/zone=${zones[$i]}" --overwrite >/dev/null
  echo "    ${node} -> zone=${zones[$i]}"
  i=$((i + 1))
done

echo
echo "==> 노드 현황 (라벨 포함)"
kubectl --context "${CTX}" get nodes -o wide
echo
echo "    node-tier / zone 라벨 확인:"
kubectl --context "${CTX}" get nodes \
  -L node-tier -L topology.kubernetes.io/zone -L node-role.kubernetes.io/control-plane

echo
echo "다음: bash phase-00-setup/scripts/02-inspect-kubeconfig.sh"
