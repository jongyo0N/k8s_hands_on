#!/usr/bin/env bash
# Phase 10 / lab 01 (로컬 대안) — kind 로 HA "결과물"을 띄워 구조를 관찰
# =============================================================================
# 재현 전제: 로컬에서 가능 (docker + kind + kubectl). kubeadm 바이너리가 있으면 설정 검증도 추가로 한다.
#   한계: kind 가 init/join/LB 를 자동화하므로 "손으로 부트스트랩하는 과정"은 못 배운다.
#         대신 완성된 HA 상태(control-plane 3 + etcd 멤버 3 + LB 컨테이너)를 눈으로 확인한다.
#   클러스터 이름은 'phase10-ha' (Phase 0 의 k8s-mastery 와 분리).
# 실행: bash phase-10-lifecycle/scripts/01b-ha-local-inspect.sh
# 옵션: KIND_IMAGE=kindest/node:v1.33.0 bash .../01b-ha-local-inspect.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="phase10-ha"
CTX="kind-${CLUSTER_NAME}"
KIND_IMAGE="${KIND_IMAGE:-kindest/node:v1.33.0}"

echo "==> 0) (kubeadm 이 로컬에 있으면) kubeadm-config.yaml 을 오프라인 검증/변환"
if command -v kubeadm >/dev/null 2>&1; then
  # config migrate 는 파싱+스키마 검증을 겸한다 (오류가 있으면 여기서 걸린다).
  kubeadm config migrate --old-config "${MANIFESTS}/kubeadm-config.yaml" --new-config /tmp/kubeadm-config.migrated.yaml \
    && echo "    kubeadm-config.yaml 파싱/검증 통과 (변환본: /tmp/kubeadm-config.migrated.yaml)"
else
  echo "    (로컬에 kubeadm 없음 — 이 단계는 건너뜀. YAML 구문 검증은 README 의 검증 절차 참고.)"
fi

echo
echo "==> 1) kind HA 클러스터 생성 (control-plane 3 + worker 2), 이미지=${KIND_IMAGE}"
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "    이미 존재함. 재생성하려면: kind delete cluster --name ${CLUSTER_NAME}"
else
  kind create cluster --config "${MANIFESTS}/kind-ha-config.yaml" --image "${KIND_IMAGE}"
fi

echo
echo "==> 2) 노드: control-plane 이 3개인지 확인"
kubectl --context "${CTX}" get nodes -o wide
kubectl --context "${CTX}" wait --for=condition=Ready nodes --all --timeout=180s || true

echo
echo "==> 3) LB 컨테이너: kind 가 자동 생성한 haproxy (VM 랩의 manifests/haproxy.cfg 에 대응)"
docker ps --filter "name=${CLUSTER_NAME}-external-load-balancer" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true

echo
echo "==> 4) controlPlaneEndpoint: 단일 apiserver 가 아니라 LB 를 가리키는지 확인"
kubectl --context "${CTX}" -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null \
  | grep -i controlPlaneEndpoint || echo "    (출력 없음 — configmap 형식이 다를 수 있음)"

echo
echo "==> 5) etcd 멤버 목록: 멤버 3개 = 쿼럼 2/3 (HA 의 핵심)"
ETCD_POD="$(kubectl --context "${CTX}" -n kube-system get pods -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${ETCD_POD}" ]]; then
  kubectl --context "${CTX}" -n kube-system exec "${ETCD_POD}" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    member list -w table || echo "    (etcdctl 호출 실패 — 노드가 아직 준비 중일 수 있음)"
else
  echo "    etcd Pod 를 찾지 못함."
fi

cat <<'EOF'

==> 해석 (VM 랩과 대응):
  - kind 가 띄운 'external-load-balancer' 컨테이너 = 우리가 VM 에서 HAProxy 로 직접 만든 LB.
  - controlPlaneEndpoint 가 그 LB 를 가리킨다 = kubeadm-config.yaml 의 controlPlaneEndpoint 핵심.
  - etcd 멤버 3개 = stacked etcd 쿼럼. 1대(노드 컨테이너)를 docker stop 해도 2/3 로 쓰기가 유지된다.
      시도: docker stop phase10-ha-control-plane2  →  kubectl 은 계속 동작, member list 는 2 unhealthy 없이 유지.
  - 그러나 "어떻게 거기까지 갔는가"(init/join/인증서 업로드)는 kind 가 감췄다 → 그게 VM 랩의 가치.

정리: bash phase-10-lifecycle/scripts/99-cleanup.sh   (phase10-ha 클러스터 삭제)
EOF
