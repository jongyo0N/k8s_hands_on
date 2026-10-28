#!/usr/bin/env bash
# Phase 10 / lab 0 — 도구 체인 점검
# 실행: bash phase-10-lifecycle/scripts/00-check-tools.sh
set -uo pipefail

echo "==> 로컬 랩(03/04, 01b 대안)에 필요한 도구"
for t in docker kind kubectl; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t  ($(command -v "$t"))"
  else
    echo "  [MISS] $t  <-- 설치 필요"
  fi
done

echo
echo "==> VM 랩(01 HA 부트스트랩 / 02 업그레이드)에 필요한 도구"
echo "    아래는 보통 '클러스터 노드(VM)' 안에 있다. 로컬 macOS 에는 없어도 된다."
for t in kubeadm etcdctl; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t  ($(command -v "$t"))"
  else
    echo "  [--]   $t  (로컬엔 없을 수 있음 — 노드에서 실행하거나, kind 에선 etcd Pod 안의 것을 쓴다)"
  fi
done

echo
echo "==> 선택 도구"
for t in multipass vcluster helm jq; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t"
  else
    echo "  [--]   $t  (해당 랩을 할 때만 필요: multipass=lab01 VM, vcluster=lab05)"
  fi
done

echo
echo "==> 버전"
docker --version 2>/dev/null || echo "  docker: (없음)"
kind --version 2>/dev/null || echo "  kind: (없음)"
kubectl version --client 2>/dev/null | head -n1 || echo "  kubectl: (없음)"

cat <<'EOF'

macOS(Homebrew) 설치 힌트:
  brew install kind kubectl helm jq
  brew install --cask multipass         # lab 01 을 VM 으로 할 때 (Ubuntu VM 생성)
  brew install vcluster                  # lab 05 (선택)
  brew install etcd                      # 로컬에 etcdctl 이 필요하면 (kind 랩은 Pod 안의 것을 써서 불필요)

VM(Ubuntu) 노드에 kubeadm/kubelet/kubectl 설치는 "노드별 minor 전용 저장소(pkgs.k8s.io)"를 쓴다:
  → 설치/핀 절차는 scripts/01a-ha-bootstrap.sh 의 'prereqs' 단계를 참고.

재현 전제 요약:
  - lab 01 (HA 부트스트랩): 본질은 VM 필요. 로컬 대안은 01b (kind 로 결과물만 관찰).
  - lab 02 (업그레이드):   본질은 VM 필요. 로컬에선 skew 규칙/순서만 학습.
  - lab 03 (etcd 백업):    kind 로 '스냅샷 저장~검증'까지 재현 가능. (복구는 옵션)
  - lab 04 (인증서):       kind 로 check-expiration / renew 재현 가능.
  - lab 05 (vCluster):     호스트 kind 클러스터 + vcluster CLI 필요 (선택).
EOF
