#!/usr/bin/env bash
# Phase 9 / 사전 점검 — 컨텍스트 / helm / 네임스페이스 / 차트 리포
# 실행: bash phase-09-observability/scripts/00-prereqs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
APP_NS="phase-09"

echo "==> 1) kind 클러스터(컨텍스트 ${CTX}) 접근 확인"
if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
  echo "    [에러] 컨텍스트 '${CTX}'로 클러스터에 접근할 수 없다."
  echo "           Phase 0의 01-create-cluster.sh로 먼저 클러스터를 만들어라."
  exit 1
fi
kubectl --context "${CTX}" get nodes

echo
echo "==> 2) 필수 도구"
for t in kubectl helm; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "    [ok]   $t ($(command -v "$t"))"
  else
    echo "    [MISS] $t <-- 설치 필요 (brew install $t)"
    exit 1
  fi
done
for t in jq curl; do
  command -v "$t" >/dev/null 2>&1 && echo "    [ok]   $t" || echo "    [--]   $t (일부 스크립트의 출력 파싱에 권장)"
done

echo
echo "==> 3) helm 리포 등록/갱신 (prometheus-community)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
echo "    사용 가능한 kube-prometheus-stack 최신 버전(상위 5개) — 핀 고정 전에 확인:"
helm search repo prometheus-community/kube-prometheus-stack --versions 2>/dev/null | head -n 6 || true

echo
echo "==> 4) 실습 네임스페이스 생성 (${APP_NS})"
kubectl --context "${CTX}" apply -f "${SCRIPT_DIR}/../manifests/00-namespace.yaml"

echo
echo "준비 완료. 다음: bash phase-09-observability/scripts/01-metrics.sh"
