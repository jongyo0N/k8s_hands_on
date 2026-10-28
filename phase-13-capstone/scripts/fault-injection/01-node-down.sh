#!/usr/bin/env bash
# 캡스톤 장애주입 1 — 워커 노드 다운 → 재스케줄 관찰 → 복구
# 실행: bash scripts/fault-injection/01-node-down.sh
set -uo pipefail
CTX="kind-k8s-mastery"; NS="capstone"
NODE_CONTAINER="k8s-mastery-worker"   # 다운시킬 kind 워커(노드=도커 컨테이너)

echo "==> 사전 상태"
kubectl --context "$CTX" get nodes
kubectl --context "$CTX" -n "$NS" get pods -o wide

echo
echo "==> 장애 주입: 워커 '${NODE_CONTAINER}' 정지"
docker stop "$NODE_CONTAINER" >/dev/null && echo "    정지됨"

echo "==> 관찰(최대 ~90s): 노드 NotReady → Pod 재스케줄 (PDB가 동시 축출 제한)"
for i in $(seq 1 9); do
  sleep 10
  echo "--- t=$((i*10))s ---"
  kubectl --context "$CTX" get nodes | grep -E 'NAME|NotReady|Ready'
  kubectl --context "$CTX" -n "$NS" get pods -o wide | grep -E 'NAME|Running|Pending|Terminating|Unknown' || true
done

echo
echo "==> 복구: 워커 재기동"
docker start "$NODE_CONTAINER" >/dev/null
echo "    재기동. 노드가 Ready로 돌아오는지 확인:"
kubectl --context "$CTX" wait --for=condition=Ready "node/${NODE_CONTAINER}" --timeout=120s || true
kubectl --context "$CTX" get nodes

echo
echo "RUNBOOK 1번 항목을 직접 채워보라: 증상→진단→원인→복구→재발방지."
