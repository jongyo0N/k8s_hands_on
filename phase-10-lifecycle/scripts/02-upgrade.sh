#!/usr/bin/env bash
# Phase 10 / lab 02 — 마이너 버전 업그레이드 (control-plane → node 순서) 체크리스트
# =============================================================================
# 재현 전제: 이 스크립트는 "클러스터 노드(VM)" 안에서, 업그레이드할 노드마다 실행한다.
#   kind 는 in-place kubeadm 업그레이드를 매끄럽게 지원하지 않는다(보통 재생성). 그래서 VM 전제.
#   로컬에서는 'skew' 단계로 버전 skew 규칙/순서만 학습할 수 있다 (노드 불필요).
#
#   순서(반드시 이 순서):
#     1) skew          (로컬 가능) 버전 skew 규칙과 "왜 control-plane 먼저인가" 출력
#     2) apply-first-cp (cp1)      첫 control-plane: repo 올림 → kubeadm 업글 → upgrade plan/apply → 노드 업글
#     3) other-cp      (cp2,cp3)   나머지 control-plane: kubeadm 업글 → `upgrade node` → 노드 업글
#     4) worker        (w1,w2)     worker: kubeadm 업글 → `upgrade node` → 노드 업글
#
#   한 번에 "한 마이너"만 올린다 (1.33 → 1.34 O, 1.33 → 1.35 X). 패치는 여러 단계 건너뛰어도 됨.
#
# 버전 핀(환경변수):
#   TO_MINOR=v1.34   TO_PKG_VERSION=1.34.0-1.1   NODE_NAME=<drain 대상 노드의 k8s 이름>
#   (예: 1.33 클러스터를 1.34 로 올린다. lab 01 로 만든 1.33 HA 클러스터에서 이어서 연습.)
# =============================================================================
set -euo pipefail

TO_MINOR="${TO_MINOR:-v1.34}"
TO_PKG_VERSION="${TO_PKG_VERSION:-1.34.0-1.1}"
TO_VERSION="v${TO_PKG_VERSION%%-*}"   # 1.34.0-1.1 → v1.34.0

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}"
  echo
  echo "사용법: bash $(basename "${BASH_SOURCE[0]}") <skew|apply-first-cp|other-cp|worker>"
}

print_skew() {
  cat <<'EOF'
==> 버전 skew 규칙 (업그레이드 순서의 근거)
  기준축은 kube-apiserver 다. 다른 모든 컴포넌트는 apiserver 보다 "최신일 수 없다".
    - kube-apiserver (HA 다중):  서로 1 마이너 이내 (업그레이드 중 과도기 허용).
    - controller-manager/scheduler/cloud-controller: apiserver 보다 "같거나 1 마이너 older".
    - kubelet / kube-proxy:       apiserver 보다 최대 3 마이너 older (1.28+). 절대 newer 금지.
    - kubectl:                    apiserver 기준 ±1 마이너.

  → 그래서 control-plane(=apiserver)을 "먼저" 올린다.
    apiserver 를 먼저 올려야 나머지(cm/scheduler/kubelet)가 "나보다 낮은" 허용 범위에 들어온다.
    반대로 kubelet 을 먼저 올리면 "kubelet > apiserver" 가 되어 skew 위반 → 지원되지 않는 상태.

  → 그래서 "한 마이너씩" 올린다.
    kubelet 이 apiserver 보다 최대 3 older 라도, 업그레이드는 마이너 건너뛰기를 지원하지 않는다
    (1.33 → 1.35 직행 X). 1.33 → 1.34 → 1.35 로 단계별.

  → 무중단의 근거:
    워크로드는 노드 kubelet+containerd 가 유지하므로, control-plane 을 한 대씩 올리는 동안
    (LB 가 살아있는 apiserver 로 돌리고) 서비스는 계속 돈다. 노드는 drain→업글→uncordon 으로
    한 대씩 비우며 교체하므로, PDB(PodDisruptionBudget)와 replica 가 충분하면 무중단.
EOF
}

# 공통: minor 전용 apt 저장소를 TO_MINOR 로 "바꿔치기" (업그레이드의 핵심 함정)
bump_repo() {
  echo "  - apt 저장소를 ${TO_MINOR} 로 변경 (pkgs.k8s.io 는 minor 별 전용 저장소다!)"
  echo "    이 한 줄을 빼먹으면 'apt 에 새 버전이 안 보여' 업그레이드가 막힌다."
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${TO_MINOR}/deb/Release.key" \
    | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${TO_MINOR}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update
}

upgrade_kubeadm_pkg() {
  echo "  - kubeadm 패키지만 먼저 ${TO_PKG_VERSION} 로 업그레이드"
  sudo apt-mark unhold kubeadm
  sudo apt-get install -y "kubeadm=${TO_PKG_VERSION}"
  sudo apt-mark hold kubeadm
  kubeadm version -o short
}

# drain → kubelet/kubectl 업글 → kubelet 재시작 → uncordon
upgrade_node_kubelet() {
  : "${NODE_NAME:?NODE_NAME 필요 (이 노드의 k8s 이름 — kubectl get nodes 의 NAME)}"
  echo "  - [drain] ${NODE_NAME} 비우기 (DaemonSet 무시, emptyDir 데이터 삭제 허용)"
  echo "    (drain/uncordon 은 kubectl 접근 가능한 아무 control-plane 에서 실행해도 된다)"
  kubectl drain "${NODE_NAME}" --ignore-daemonsets --delete-emptydir-data --timeout=120s

  echo "  - [kubelet/kubectl 업글] ${TO_PKG_VERSION}"
  sudo apt-mark unhold kubelet kubectl
  sudo apt-get install -y "kubelet=${TO_PKG_VERSION}" "kubectl=${TO_PKG_VERSION}"
  sudo apt-mark hold kubelet kubectl

  echo "  - [kubelet 재시작]"
  sudo systemctl daemon-reload
  sudo systemctl restart kubelet

  echo "  - [uncordon] ${NODE_NAME} 다시 스케줄 가능하게"
  kubectl uncordon "${NODE_NAME}"
  echo "  완료: kubectl get nodes 에서 ${NODE_NAME} 이 ${TO_VERSION} 로 보이는지 확인."
}

step_apply_first_cp() {
  echo "==> [apply-first-cp] 첫 control-plane(cp1) 업그레이드 → ${TO_VERSION}"
  bump_repo
  upgrade_kubeadm_pkg
  echo "  - [plan] 무엇이 올라갈지 미리보기"
  sudo kubeadm upgrade plan
  echo "  - [apply] 첫 control-plane 에서만 'apply' (etcd/인증서/정적 Pod 매니페스트를 갱신)"
  sudo kubeadm upgrade apply "${TO_VERSION}" -y
  upgrade_node_kubelet
}

step_other_cp() {
  echo "==> [other-cp] 나머지 control-plane(cp2/cp3) 업그레이드 → ${TO_VERSION}"
  bump_repo
  upgrade_kubeadm_pkg
  echo "  - [upgrade node] 2번째 이후 control-plane 은 'apply' 가 아니라 'upgrade node'"
  sudo kubeadm upgrade node
  upgrade_node_kubelet
}

step_worker() {
  echo "==> [worker] worker(w1/w2) 업그레이드 → ${TO_VERSION}"
  bump_repo
  upgrade_kubeadm_pkg
  echo "  - [upgrade node] worker 도 'upgrade node' (로컬 kubelet 설정만 갱신)"
  sudo kubeadm upgrade node
  upgrade_node_kubelet
}

case "${1:-}" in
  skew)           print_skew ;;
  apply-first-cp) step_apply_first_cp ;;
  other-cp)       step_other_cp ;;
  worker)         step_worker ;;
  *)              usage ; exit 1 ;;
esac
