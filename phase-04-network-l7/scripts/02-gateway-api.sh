#!/usr/bin/env bash
# Phase 4 / lab 2 — Gateway API: 경로 기반 라우팅 + 가중치 90/10 트래픽 분할
# 실행: bash phase-04-network-l7/scripts/02-gateway-api.sh
# 전제: lab 01 완료(Cilium + kube-proxy replacement 설치됨).
# 옵션:
#   GWAPI_VERSION=v1.6.3 CILIUM_VERSION=1.20.4 bash .../02-gateway-api.sh
#
# Ref: https://gateway-api.sigs.k8s.io/
#      https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests/gateway"
CLUSTER_NAME="k8s-l7"
CTX="kind-${CLUSTER_NAME}"

# 버전 핀.
#   Gateway API 최신: https://github.com/kubernetes-sigs/gateway-api/releases
#   Cilium 최신:      https://github.com/cilium/cilium/releases
GWAPI_VERSION="${GWAPI_VERSION:-v1.6.3}"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"

echo "==> 1) Gateway API CRD 설치 (standard 채널, 공식 릴리스에서 버전 핀)"
echo "    GatewayClass / Gateway / HTTPRoute 등의 CRD를 먼저 깐다 (Cilium보다 먼저)."
kubectl --context "${CTX}" apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VERSION}/standard-install.yaml"

echo
echo "==> 2) Cilium의 Gateway API 컨트롤러 활성화 (helm upgrade + 재기동)"
echo "    기존 값 보존(--reuse-values) 위에 gatewayAPI.enabled=true 만 더한다."
helm upgrade cilium cilium/cilium --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true
kubectl --context "${CTX}" -n kube-system rollout restart deployment/cilium-operator
kubectl --context "${CTX}" -n kube-system rollout restart ds/cilium
kubectl --context "${CTX}" -n kube-system rollout status ds/cilium --timeout=180s

echo
echo "==> 3) 'cilium' GatewayClass 확인 (ACCEPTED=True 여야 함)"
kubectl --context "${CTX}" get gatewayclass

echo
echo "==> 4) 백엔드(v1/v2) + Gateway + HTTPRoute(경로/가중치) 적용"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-backends.yaml"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/10-gateway.yaml"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/20-httproute-path.yaml"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/21-httproute-weighted.yaml"

echo
echo "==> 5) Gateway가 프로그래밍될 때까지 대기 (condition=Programmed)"
kubectl --context "${CTX}" -n gw-demo rollout status deploy/echo-v1 --timeout=120s
kubectl --context "${CTX}" -n gw-demo rollout status deploy/echo-v2 --timeout=120s
kubectl --context "${CTX}" -n gw-demo wait --for=condition=Programmed gateway/web-gw --timeout=120s || true
kubectl --context "${CTX}" -n gw-demo get gateway,httproute

echo
echo "==> 6) 검증 — Cilium이 만든 LB Service로 port-forward 후 curl"
echo "    (kind엔 외부 LB가 없어 EXTERNAL-IP는 <pending>. 그래서 port-forward로 검증한다."
echo "     진짜 EXTERNAL-IP가 필요하면 manifests/gateway/90-lb-ippool.yaml 참고.)"
GW_SVC="cilium-gateway-web-gw"   # Cilium은 'cilium-gateway-<gateway이름>' Service를 만든다
PF_PID=""
cleanup() { [ -n "${PF_PID}" ] && kill "${PF_PID}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

if kubectl --context "${CTX}" -n gw-demo get svc "${GW_SVC}" >/dev/null 2>&1; then
  kubectl --context "${CTX}" -n gw-demo port-forward "svc/${GW_SVC}" 8080:80 >/dev/null 2>&1 &
  PF_PID=$!
  sleep 3
  echo "    [경로 라우팅]"
  echo "      GET /v1 -> $(curl -s --max-time 5 http://127.0.0.1:8080/v1 || echo '(실패)')"
  echo "      GET /v2 -> $(curl -s --max-time 5 http://127.0.0.1:8080/v2 || echo '(실패)')"
  echo "    [가중치 분할 /split — 20회, v1≈18 / v2≈2 기대]"
  for _ in $(seq 1 20); do curl -s --max-time 5 http://127.0.0.1:8080/split; echo; done \
    | sort | uniq -c || true
else
  echo "    ${GW_SVC} Service가 아직 없음. 잠시 후 아래로 수동 확인:"
  echo "      kubectl -n gw-demo get svc | grep cilium-gateway"
fi

cat <<EOF

해석 포인트 (NOTES.md):
  - Ingress는 'rules' 한 덩어리 + 벤더 어노테이션이었다. Gateway API는
    GatewayClass(구현체) / Gateway(리스너) / HTTPRoute(규칙)로 '역할'을 쪼갰다.
  - 가중치 분할/헤더 매칭/트래픽 미러링이 '표준 필드'다 (어노테이션 지옥 탈출).
  - weight는 상대 비율 — 90/10은 9:1. 표본이 작으면 정확히 안 맞을 수 있다.

다음: bash phase-04-network-l7/scripts/03-netpol-default-deny.sh
EOF
