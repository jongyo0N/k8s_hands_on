#!/usr/bin/env bash
# Phase 7 / lab 5 (선택, 사전 준비) — KEDA 설치 (helm)
# 실행: bash phase-07-scheduling/scripts/05-keda-install.sh
#
# KEDA = Kubernetes Event-Driven Autoscaling. HPA가 못 하는 "0까지 축소"와
# 외부 이벤트(큐 길이, cron, Prometheus 쿼리 등) 기반 스케일을 더해준다.
set -euo pipefail

CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"

# 차트 버전 핀. 최신 확인: https://github.com/kedacore/charts/releases
# (2026-10 기준 최신 = 2.21.0. app 버전도 동일 라인.)
KEDA_CHART_VERSION="${KEDA_CHART_VERSION:-2.21.0}"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm 이 필요하다: brew install helm" >&2
  exit 1
fi

echo "==> 1) kedacore helm 저장소 추가/갱신"
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
helm repo update kedacore >/dev/null

echo
echo "==> 2) KEDA ${KEDA_CHART_VERSION} 설치 (namespace: keda)"
helm upgrade --install keda kedacore/keda \
  --kube-context "${CTX}" \
  --namespace keda --create-namespace \
  --version "${KEDA_CHART_VERSION}" \
  --wait --timeout 180s

echo
echo "==> 3) KEDA 구성요소 / CRD 확인"
kubectl --context "${CTX}" -n keda get deploy 2>/dev/null || true
echo
kubectl --context "${CTX}" get crd 2>/dev/null | grep -E 'keda\.sh' || echo "    (scaledobjects.keda.sh CRD 미발견 — 설치 로그 확인)"

echo
echo "다음: bash phase-07-scheduling/scripts/05-keda-scaledobject.sh"
