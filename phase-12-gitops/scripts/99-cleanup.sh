#!/usr/bin/env bash
# Phase 12 — 정리 (Argo CD / Rollouts / 워크로드 제거)
# 실행: bash phase-12-gitops/scripts/99-cleanup.sh
# 옵션: KEEP_ARGOCD=1 bash .../99-cleanup.sh   (Argo CD/Rollouts 컨트롤러는 남기고 앱만 정리)
set -euo pipefail

CTX="kind-k8s-mastery"
# 버전 핀(설치 때와 동일해야 uninstall 매니페스트가 맞는다).
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.6}"
ROLLOUTS_VERSION="${ROLLOUTS_VERSION:-v1.10.1}"

echo "==> 1) ApplicationSet / Application 삭제 (finalizer가 워크로드까지 연쇄 삭제)"
# 컨트롤러가 살아있을 때 먼저 지워야 finalizer가 풀린다(순서 중요).
kubectl --context "${CTX}" -n argocd delete applicationset --all --ignore-not-found=true --timeout=120s || true
kubectl --context "${CTX}" -n argocd delete application --all --ignore-not-found=true --timeout=180s || true

echo
echo "==> 2) Rollouts 리소스 삭제 (phase-12)"
kubectl --context "${CTX}" -n phase-12 delete rollout,analysistemplate,analysisrun --all --ignore-not-found=true || true

if [ "${KEEP_ARGOCD:-0}" = "1" ]; then
  echo
  echo "==> (KEEP_ARGOCD=1) 컨트롤러는 유지. 앱/워크로드만 정리하고 종료."
  exit 0
fi

echo
echo "==> 3) Argo CD 컨트롤러 제거"
kubectl --context "${CTX}" delete -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" \
  --ignore-not-found=true || true

echo
echo "==> 4) Argo Rollouts 컨트롤러 제거"
kubectl --context "${CTX}" delete -n argo-rollouts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml" \
  --ignore-not-found=true || true

echo
echo "==> 5) 네임스페이스 삭제"
for ns in phase-12 phase-12-dev phase-12-stg phase-12-prod argocd argo-rollouts; do
  kubectl --context "${CTX}" delete namespace "${ns}" --ignore-not-found=true --timeout=120s || true
done

echo
echo "완료. (클러스터 자체를 지우려면 Phase 0의 99-cleanup.sh)"
