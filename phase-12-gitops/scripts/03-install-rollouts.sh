#!/usr/bin/env bash
# Phase 12 / lab 3 — Argo Rollouts 설치 (버전 핀) + Rollout/Analysis 배포
# 실행: bash phase-12-gitops/scripts/03-install-rollouts.sh
# 옵션: ROLLOUTS_VERSION=v1.10.1 bash .../03-install-rollouts.sh  (버전 고정)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="argo-rollouts"
WL_NS="phase-12"
# 버전 핀. 최신 확인: https://github.com/argoproj/argo-rollouts/releases  (작성 시점 기준 v1.10.1)
ROLLOUTS_VERSION="${ROLLOUTS_VERSION:-v1.10.1}"
INSTALL_URL="https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml"

echo "==> Argo Rollouts ${ROLLOUTS_VERSION} 컨트롤러 설치 (네임스페이스 ${NS})"
echo "    매니페스트: ${INSTALL_URL}"
kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f -
kubectl --context "${CTX}" apply -n "${NS}" -f "${INSTALL_URL}"

echo
echo "==> 컨트롤러 Ready 대기"
kubectl --context "${CTX}" -n "${NS}" rollout status deployment/argo-rollouts --timeout=300s

echo
echo "==> Rollout / AnalysisTemplate / Service 배포 (${WL_NS} 네임스페이스)"
kubectl --context "${CTX}" create namespace "${WL_NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f -
kubectl --context "${CTX}" apply -n "${WL_NS}" \
  -f "${SCRIPT_DIR}/../manifests/03-rollouts/analysis-template.yaml" \
  -f "${SCRIPT_DIR}/../manifests/03-rollouts/service.yaml" \
  -f "${SCRIPT_DIR}/../manifests/03-rollouts/rollout.yaml"

echo
echo "==> 최초 롤아웃이 안정화될 때까지 대기 (첫 배포는 canary 단계 없이 바로 뜬다)"
kubectl --context "${CTX}" -n "${WL_NS}" rollout status rollout/web --timeout=180s 2>/dev/null \
  || kubectl --context "${CTX}" -n "${WL_NS}" get rollout/web

cat <<EOF

참고:
  - Rollout 상태를 예쁘게 보려면 플러그인 설치 후:
      kubectl --context ${CTX} argo rollouts get rollout web -n ${WL_NS} --watch
  - AnalysisTemplate(success-rate)는 Prometheus 주소를 플레이스홀더로 둔다.
    Prometheus가 없으면 canary의 analysis 단계에서 AnalysisRun이 Error가 나고
    Rollout이 자동 롤백된다 → 이게 바로 "관측성이 선행조건"이라는 뜻(완료 기준).
    실제 분석을 돌리려면 Phase 9에서 kube-prometheus-stack을 깔고
    manifests/03-rollouts/analysis-template.yaml 의 address/query를 맞춘다.

다음: bash phase-12-gitops/scripts/03b-canary-observe.sh
EOF
