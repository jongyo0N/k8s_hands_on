#!/usr/bin/env bash
# Phase 6 / lab 0 — 네임스페이스/컨텍스트 준비 + 도구 점검
# 실행: bash phase-06-config/scripts/00-setup.sh
set -euo pipefail

CTX="kind-k8s-mastery"
NS="phase-06"

echo "==> 컨텍스트 확인: ${CTX}"
kubectl config get-contexts "${CTX}" >/dev/null 2>&1 || {
  echo "    [에러] 컨텍스트 ${CTX} 가 없음."
  echo "           Phase 0의 scripts/01-create-cluster.sh 로 클러스터를 먼저 만들 것."
  exit 1
}

echo
echo "==> 네임스페이스 ${NS} 생성 (있으면 재사용)"
kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f -

echo
echo "==> 이 Phase에서 쓰는 도구 점검"
if command -v helm >/dev/null 2>&1; then
  echo "  [ok]   helm ($(helm version --short 2>/dev/null))"
else
  echo "  [MISS] helm  <-- lab 1(Reloader)/3(ESO)/4(Helm)에 필요: brew install helm"
fi
if command -v kustomize >/dev/null 2>&1; then
  echo "  [ok]   kustomize"
elif kubectl kustomize --help >/dev/null 2>&1; then
  echo "  [ok]   kustomize (독립 바이너리는 없지만 kubectl 내장 'kubectl kustomize' 사용 가능)"
else
  echo "  [MISS] kustomize  <-- lab 4에 필요: brew install kustomize"
fi
if command -v docker >/dev/null 2>&1; then
  echo "  [ok]   docker (lab 2에서 control-plane 컨테이너 접근에 필요)"
else
  echo "  [MISS] docker  <-- lab 2(etcd 직접 열기)에 필요"
fi

echo
echo "준비 완료. 다음: bash phase-06-config/scripts/01-configmap-env-vs-volume.sh"
