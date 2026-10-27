#!/usr/bin/env bash
# Phase 5 / lab 0 — 준비: 컨텍스트 확인 + namespace 생성 + 기본 StorageClass 점검
# 실행: bash phase-05-storage/scripts/00-prep.sh
# 전제: Phase 0의 kind 클러스터(context kind-k8s-mastery)가 떠 있어야 한다.
set -euo pipefail

CTX="kind-k8s-mastery"
NS="phase-05"

echo "==> 1) 클러스터 접속 확인 (context: ${CTX})"
if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
  echo "    [실패] '${CTX}' 클러스터에 접속할 수 없다."
  echo "    Phase 0에서 먼저 클러스터를 만들어라:"
  echo "      bash phase-00-setup/scripts/01-create-cluster.sh"
  exit 1
fi
echo "    ok"

echo
echo "==> 2) namespace '${NS}' 생성 (idempotent)"
kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f -

echo
echo "==> 3) 기본 StorageClass 점검 — kind 'standard'는 이미 local-path + WFFC 다"
kubectl --context "${CTX}" get storageclass
echo
echo "    standard의 provisioner / volumeBindingMode:"
kubectl --context "${CTX}" get storageclass standard \
  -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner,BINDINGMODE:.volumeBindingMode,RECLAIM:.reclaimPolicy'

cat <<'EOF'

    해석: 'standard'의 provisioner는 rancher.io/local-path, volumeBindingMode는
          WaitForFirstConsumer 다. 즉 kind는 "올바른 기본값"을 준다.
          lab 1에서는 이 기본값과 대조하기 위해 Immediate SC를 일부러 하나 더 만든다.
EOF

echo
echo "다음: bash phase-05-storage/scripts/01-wffc-vs-immediate.sh"
