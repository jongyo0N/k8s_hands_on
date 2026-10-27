#!/usr/bin/env bash
# Phase 4 / lab 1 — Cilium를 CNI로 설치 (kube-proxy replacement) + Hubble 활성화
# 실행: bash phase-04-network-l7/scripts/01-install-cilium.sh
# 옵션:
#   CILIUM_VERSION=1.20.4 bash .../01-install-cilium.sh   # Cilium 버전 고정
#   KIND_IMAGE=kindest/node:v1.34.0 bash .../01-install-cilium.sh  # 노드 이미지 고정
#
# Ref: https://docs.cilium.io/en/stable/installation/kind/
#      https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="k8s-l7"
CTX="kind-${CLUSTER_NAME}"
CP="${CLUSTER_NAME}-control-plane"
CONFIG="${SCRIPT_DIR}/../kind-cilium.yaml"

# 버전 핀 (최신은 https://github.com/cilium/cilium/releases 에서 확인).
CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"

echo "==> 1) kind 클러스터 '${CLUSTER_NAME}' 생성 (CNI 없음 / kube-proxy 없음)"
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "    이미 존재함. 새로 만들려면 먼저 99-cleanup.sh 실행."
else
  kind create cluster --config "${CONFIG}" ${KIND_IMAGE:+--image "${KIND_IMAGE}"}
fi

echo
echo "==> 2) 설치 직후 상태 관찰 (CNI가 없으니 비정상이 '정상')"
echo "    노드는 NotReady, CoreDNS는 Pending 일 것이다 — Cilium이 아직 없기 때문:"
kubectl --context "${CTX}" get nodes
kubectl --context "${CTX}" -n kube-system get pods -l k8s-app=kube-dns 2>/dev/null || true

echo
echo "==> 3) API server 주소 알아내기 (kube-proxy가 없어 'kubernetes' ClusterIP를"
echo "       Cilium이 아직 못 뚫는다 → 부트스트랩용 실주소를 직접 넘겨야 한다)"
# kind 노드는 'kind' 도커 네트워크 위의 컨테이너다. control-plane 컨테이너의
# 네트워크 IP + 컨테이너 내부 포트 6443 이 클러스터 내부에서 도달 가능한 주소.
# (kubectl cluster-info 가 주는 127.0.0.1:<random> 은 호스트 매핑이라 Pod에선 못 쓴다.)
API_SERVER_IP="$(docker inspect "${CP}" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
API_SERVER_PORT=6443
echo "    API_SERVER=${API_SERVER_IP}:${API_SERVER_PORT}"

echo
echo "==> 4) Helm 레포 등록 + Cilium 설치 (kube-proxy replacement + Hubble)"
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium >/dev/null
helm install cilium cilium/cilium --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${API_SERVER_IP}" \
  --set k8sServicePort="${API_SERVER_PORT}" \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

echo
echo "==> 5) Cilium 기동 대기"
kubectl --context "${CTX}" -n kube-system rollout status ds/cilium --timeout=180s
kubectl --context "${CTX}" -n kube-system rollout status deploy/cilium-operator --timeout=180s

echo
echo "==> 6) 이제 노드가 Ready 가 된다 (Cilium이 Pod 네트워크를 세웠으므로)"
kubectl --context "${CTX}" wait --for=condition=Ready nodes --all --timeout=180s
kubectl --context "${CTX}" get nodes -o wide

echo
echo "==> 7) kube-proxy replacement가 켜졌는지 확인 (True 여야 함)"
echo "    cilium CLI가 있으면:  cilium status --wait"
kubectl --context "${CTX}" -n kube-system exec ds/cilium -- cilium-dbg status \
  | grep -iE 'KubeProxyReplacement|Routing|Host firewall|Masquerading' || true

cat <<EOF

==> 8) Hubble로 플로우 관측 (관측성 = Cilium의 강점)
    (a) 포트포워드:    cilium hubble port-forward &        # 또는 아래 kubectl
        kubectl --context ${CTX} -n kube-system port-forward svc/hubble-relay 4245:80 &
    (b) 실시간 플로우:  hubble observe --follow
    (c) 특정 네임스페이스만:  hubble observe --namespace netpol-demo --follow
    (d) UI:            cilium hubble ui        # 브라우저로 서비스 맵 관측
    → lab 03(NetworkPolicy)에서 'DROPPED' 플로우를 눈으로 확인하면 학습 효과가 크다.

다음: bash phase-04-network-l7/scripts/02-gateway-api.sh
EOF
