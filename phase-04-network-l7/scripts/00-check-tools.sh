#!/usr/bin/env bash
# Phase 4 / lab 0 — 도구 체인 점검
# 실행: bash phase-04-network-l7/scripts/00-check-tools.sh
set -uo pipefail

echo "==> 필수 도구 (Phase 4에 반드시 필요)"
for t in docker kind kubectl helm; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t  ($(command -v "$t"))"
  else
    echo "  [MISS] $t  <-- 설치 필요"
  fi
done

echo
echo "==> 권장 도구 (관측/편의 — 없으면 kubectl로 대체 가능)"
# cilium : Cilium CLI (cilium status / cilium hubble ...). 버전은 agent와 '독립'이다.
# hubble : Hubble CLI (hubble observe) — 플로우 관측용.
for t in cilium hubble jq; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t"
  else
    echo "  [--]   $t  (선택 — kubectl ex 로 대체 가능)"
  fi
done

echo
echo "==> 버전"
kind --version 2>/dev/null || echo "  kind: (없음)"
kubectl version --client 2>/dev/null | head -n1 || echo "  kubectl: (없음)"
helm version --short 2>/dev/null || echo "  helm: (없음)"
cilium version --client 2>/dev/null | head -n1 || echo "  cilium CLI: (없음, 선택)"

echo
echo "macOS(Homebrew) 설치 힌트:"
echo "  brew install kind kubectl helm"
echo "  brew install cilium-cli hubble     # Cilium/Hubble CLI (선택이지만 권장)"
echo
echo "참고: kube-proxy replacement의 Socket LB는 호스트 커널/‑cgroup 요건이 있다."
echo "      (cgroup v2 + 커널 5.14+ 권장). Docker Desktop/OrbStack/Colima 최신 VM은 대개 충족."
echo "      Ref: https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/"

echo
echo "다음: bash phase-04-network-l7/scripts/01-install-cilium.sh"
