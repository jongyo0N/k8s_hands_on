#!/usr/bin/env bash
# Phase 7 / lab 4 (사전 준비) — metrics-server 설치 (kind 패치 포함)
# 실행: bash phase-07-scheduling/scripts/04-metrics-server-install.sh
#
# HPA(cpu/memory)와 `kubectl top` 은 metrics-server 가 제공하는 metrics.k8s.io API에
# 의존한다. 기본 클러스터엔 없으므로 여기서 설치한다.
set -euo pipefail

CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"

# 버전 핀. 최신 확인: https://github.com/kubernetes-sigs/metrics-server/releases
# (2026-10 기준 최신 stable = v0.9.0. 올릴 땐 아래 한 줄만 바꾸면 된다.)
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-v0.9.0}"
URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

echo "==> 1) metrics-server ${METRICS_SERVER_VERSION} 설치"
echo "    ${URL}"
kubectl --context "${CTX}" apply -f "${URL}"

echo
echo "==> 2) kind 전용 패치: --kubelet-insecure-tls"
echo "    kind의 kubelet serving 인증서는 클러스터 CA가 서명한 게 아니라 self-signed 라서"
echo "    metrics-server가 kubelet(:10250) 스크레이프 시 TLS 검증에 실패한다."
echo "    로컬 학습 환경이므로 검증을 끈다. (프로덕션에선 kubelet serving cert를"
echo "    제대로 서명하도록 구성하고 이 플래그를 쓰지 않는다.)"
if kubectl --context "${CTX}" -n kube-system get deployment metrics-server \
     -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q 'kubelet-insecure-tls'; then
  echo "    이미 패치됨 — 건너뜀."
else
  kubectl --context "${CTX}" -n kube-system patch deployment metrics-server \
    --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  echo "    패치 완료."
fi

echo
echo "==> 3) metrics-server 롤아웃 대기"
kubectl --context "${CTX}" -n kube-system rollout status deployment/metrics-server --timeout=120s

echo
echo "==> 4) metrics API 가 실제로 값을 돌려줄 때까지 대기 (수집까지 20~40초 걸린다)"
ok=""
for _ in $(seq 1 30); do
  if kubectl --context "${CTX}" top nodes >/dev/null 2>&1; then ok="yes"; break; fi
  printf "."; sleep 3
done
echo
if [ -n "${ok}" ]; then
  echo "    metrics 준비 완료:"
  kubectl --context "${CTX}" top nodes
else
  echo "    아직 metrics 미준비. 잠시 후 'kubectl --context ${CTX} top nodes' 로 재확인."
fi

echo
echo "다음: bash phase-07-scheduling/scripts/04-hpa-behavior.sh"
