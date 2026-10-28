#!/usr/bin/env bash
# Phase 12 / lab 0 — 도구 체인 점검
# 실행: bash phase-12-gitops/scripts/00-check-tools.sh
set -uo pipefail

CTX="kind-k8s-mastery"

echo "==> 필수 도구 (Phase 12에 반드시 필요)"
for t in kubectl git curl python3; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t  ($(command -v "$t"))"
  else
    echo "  [MISS] $t  <-- 설치 필요"
  fi
done

echo
echo "==> 권장 도구 (랩을 더 편하게 — 없어도 kubectl로 대체 가능)"
# argocd       : Argo CD CLI (로그인/동기화/진단). 없으면 kubectl + UI로 대체.
# kubectl-argo-rollouts : Rollouts kubectl 플러그인 (get/promote/abort 시각화).
# kustomize    : 오버레이 로컬 렌더 확인용 (kubectl kustomize로도 됨).
for t in argocd kubectl-argo-rollouts kustomize jq; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t"
  else
    echo "  [--]   $t  (선택)"
  fi
done

echo
echo "==> Phase 0 클러스터(컨텍스트 ${CTX}) 확인"
if kubectl config get-contexts -o name 2>/dev/null | grep -qx "${CTX}"; then
  echo "  [ok]   컨텍스트 ${CTX} 존재"
  kubectl --context "${CTX}" get nodes >/dev/null 2>&1 \
    && echo "  [ok]   API server 응답" \
    || echo "  [MISS] API server 응답 없음 — Phase 0의 01-create-cluster.sh로 클러스터를 먼저 띄운다."
else
  echo "  [MISS] 컨텍스트 ${CTX} 없음 — Phase 0에서 kind 클러스터를 먼저 생성한다."
fi

echo
echo "macOS(Homebrew) 설치 힌트:"
echo "  brew install argocd kustomize jq"
echo "  Rollouts 플러그인: brew install argoproj/tap/kubectl-argo-rollouts"
echo "                     (또는) kubectl krew install argo-rollouts"
echo
echo "다음: bash phase-12-gitops/scripts/01-install-argocd.sh"
