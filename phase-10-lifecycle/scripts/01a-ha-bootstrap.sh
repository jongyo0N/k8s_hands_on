#!/usr/bin/env bash
# Phase 10 / lab 01 — kubeadm HA control-plane 부트스트랩 (VM 런북)
# =============================================================================
# 재현 전제: 이 스크립트는 "클러스터 노드(VM)" 안에서 실행한다. 로컬 macOS 가 아니다.
#   권장: multipass 로 Ubuntu VM 6대 (LB 1 + control-plane 3 + worker 2).
#     multipass launch 22.04 --name cp1 --cpus 2 --memory 2G --disk 10G   (cp2,cp3,w1,w2,lb 동일)
#   각 VM 에 이 레포를 복사하거나 이 스크립트를 scp 해서, "역할에 맞는 단계"를 실행한다.
#
#   단계(=첫 번째 인자):
#     prereqs     모든 k8s 노드(cp*, w*)에서 1회 — 커널 모듈/sysctl/swap off/containerd/kubeadm 설치
#     lb          LB VM 에서 — HAProxy 설치 + manifests/haproxy.cfg 적용
#     init        cp1 에서 1회 — kubeadm init(--upload-certs) + CNI 설치 + join 명령 출력
#     join-cp     cp2, cp3 에서 — control-plane 으로 join (--control-plane --certificate-key)
#     join-worker w1, w2 에서 — worker 로 join
#
#   kind 로 "결과물만" 보고 싶으면 → scripts/01b-ha-local-inspect.sh (로컬 가능).
#
# 버전 핀(환경변수로 덮어쓰기 가능):
#   K8S_MINOR=v1.33   KUBE_PKG_VERSION=1.33.0-1.1   CALICO_VERSION=v3.28.2
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"

K8S_MINOR="${K8S_MINOR:-v1.33}"
KUBE_PKG_VERSION="${KUBE_PKG_VERSION:-1.33.0-1.1}"   # apt 패키지 버전 (minor 는 K8S_MINOR 와 일치해야 함)
CALICO_VERSION="${CALICO_VERSION:-v3.28.2}"
CONFIG="${MANIFESTS}/kubeadm-config.yaml"

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}"
  echo
  echo "사용법: bash $(basename "${BASH_SOURCE[0]}") <prereqs|lb|init|join-cp|join-worker>"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    echo "이 단계는 root 권한이 필요하다 (sudo 또는 root 로 실행)." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
step_prereqs() {
  need_root
  echo "==> [prereqs] 커널 모듈 / sysctl / swap off / containerd / kubeadm·kubelet·kubectl 설치"

  echo "  - 커널 모듈 (overlay, br_netfilter)"
  cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter

  echo "  - sysctl (브리지 netfilter + ip_forward)"
  cat <<'EOF' | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system >/dev/null

  echo "  - swap off (kubelet 은 기본적으로 swap 이 켜져 있으면 뜨지 않는다)"
  sudo swapoff -a
  sudo sed -i.bak '/\bswap\b/ s/^\(.*\)$/#\1/' /etc/fstab || true

  echo "  - containerd 설치 + SystemdCgroup=true (kubelet cgroupDriver=systemd 와 일치시킴)"
  sudo apt-get update
  sudo apt-get install -y containerd
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd

  echo "  - kube 저장소(pkgs.k8s.io, minor 전용) 등록 + 버전 핀 설치 + hold"
  sudo apt-get install -y apt-transport-https ca-certificates curl gpg
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y "kubelet=${KUBE_PKG_VERSION}" "kubeadm=${KUBE_PKG_VERSION}" "kubectl=${KUBE_PKG_VERSION}"
  # hold: 자동 업그레이드로 버전이 어긋나는 사고를 막는다 (업그레이드는 lab 02 에서 의도적으로 unhold).
  sudo apt-mark hold kubelet kubeadm kubectl
  sudo systemctl enable kubelet
  echo "  완료. kubeadm 버전: $(kubeadm version -o short 2>/dev/null || echo '?')"
}

# ---------------------------------------------------------------------------
step_lb() {
  need_root
  echo "==> [lb] HAProxy 설치 + control-plane 로드밸런서 구성"
  sudo apt-get update
  sudo apt-get install -y haproxy
  sudo cp "${MANIFESTS}/haproxy.cfg" /etc/haproxy/haproxy.cfg
  sudo systemctl restart haproxy
  sudo systemctl enable haproxy
  echo "  완료. 상태 페이지: http://<LB_IP>:8404/stats"
  echo "  주의: haproxy.cfg 의 backend IP(cp1/cp2/cp3)를 실제 VM IP 로 맞췄는지 확인."
}

# ---------------------------------------------------------------------------
step_init() {
  need_root
  echo "==> [init] cp1 에서 kubeadm init (--upload-certs) + CNI(Calico) 설치"
  echo "  설정 파일: ${CONFIG}"
  echo "  (controlPlaneEndpoint / advertiseAddress / podSubnet 를 환경에 맞게 수정했는지 확인)"
  sudo kubeadm init --config "${CONFIG}" --upload-certs | tee /tmp/kubeadm-init.out

  echo
  echo "  - 현재 사용자용 kubeconfig 설치"
  mkdir -p "${HOME}/.kube"
  sudo cp -f /etc/kubernetes/admin.conf "${HOME}/.kube/config"
  sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config"

  echo "  - CNI 설치 (Calico ${CALICO_VERSION} — podSubnet 192.168.0.0/16 과 일치)"
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

  cat <<'EOF'

  다음 할 일:
    1) /tmp/kubeadm-init.out 에서 두 종류의 join 명령을 확인한다:
       - "kubeadm join ... --control-plane --certificate-key ..."  → cp2, cp3 용
       - "kubeadm join ..."                                        → w1, w2 용
    2) 토큰/인증서키가 만료됐으면(2h) 재발급:
       - 워커 토큰:        kubeadm token create --print-join-command
       - control-plane 키: sudo kubeadm init phase upload-certs --upload-certs   (새 certificate-key 출력)
    3) cp2/cp3 에서 join-cp, w1/w2 에서 join-worker 단계를 실행한다.
       (이 스크립트의 join-* 단계는 아래 환경변수를 받는다.)
EOF
}

# ---------------------------------------------------------------------------
# join 공통: 아래 환경변수가 필요하다 (init 출력에서 복사).
#   CP_ENDPOINT=10.0.0.10:6443  JOIN_TOKEN=...  CA_CERT_HASH=sha256:...  (+cp 는 CERT_KEY=...)
require_join_vars() {
  : "${CP_ENDPOINT:?CP_ENDPOINT 필요 (예: 10.0.0.10:6443, = controlPlaneEndpoint)}"
  : "${JOIN_TOKEN:?JOIN_TOKEN 필요 (init 출력의 --token 값)}"
  : "${CA_CERT_HASH:?CA_CERT_HASH 필요 (init 출력의 --discovery-token-ca-cert-hash 값)}"
}

step_join_cp() {
  need_root
  require_join_vars
  : "${CERT_KEY:?CERT_KEY 필요 (--upload-certs 로 나온 --certificate-key 값)}"
  : "${NODE_IP:?NODE_IP 필요 (이 control-plane 노드의 IP, 예: 10.0.0.12)}"
  echo "==> [join-cp] control-plane 으로 클러스터 join"
  sudo kubeadm join "${CP_ENDPOINT}" \
    --token "${JOIN_TOKEN}" \
    --discovery-token-ca-cert-hash "${CA_CERT_HASH}" \
    --control-plane --certificate-key "${CERT_KEY}" \
    --apiserver-advertise-address "${NODE_IP}"
  echo "  완료. cp1 에서: kubectl get nodes 로 control-plane 3개가 보이는지 확인."
}

step_join_worker() {
  need_root
  require_join_vars
  echo "==> [join-worker] worker 로 클러스터 join"
  sudo kubeadm join "${CP_ENDPOINT}" \
    --token "${JOIN_TOKEN}" \
    --discovery-token-ca-cert-hash "${CA_CERT_HASH}"
  echo "  완료."
}

# ---------------------------------------------------------------------------
case "${1:-}" in
  prereqs)     step_prereqs ;;
  lb)          step_lb ;;
  init)        step_init ;;
  join-cp)     step_join_cp ;;
  join-worker) step_join_worker ;;
  *)           usage ; exit 1 ;;
esac
