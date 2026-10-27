#!/usr/bin/env bash
# Phase 0 / lab 0 — 도구 체인 점검
# 실행: bash phase-00-setup/scripts/00-check-tools.sh
set -uo pipefail

echo "==> 필수 도구 (Phase 0에 반드시 필요)"
for t in docker kind kubectl openssl; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t  ($(command -v "$t"))"
  else
    echo "  [MISS] $t  <-- 설치 필요"
  fi
done

echo
echo "==> 권장 도구 (이후 Phase에서 사용)"
for t in helm kustomize k9s stern jq yq; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t"
  else
    echo "  [--]   $t  (Phase 0에서는 선택)"
  fi
done

echo
echo "==> 버전"
docker --version 2>/dev/null || echo "  docker: (없음)"
kind --version 2>/dev/null || echo "  kind: (없음)"
kubectl version --client 2>/dev/null | head -n1 || echo "  kubectl: (없음)"

echo
echo "macOS(Homebrew) 설치 힌트:"
echo "  brew install kind kubectl helm kustomize k9s stern jq yq"
echo "  컨테이너 런타임: Docker Desktop / OrbStack / Colima 중 택1 (README의 트레이드오프 참고)"
echo "  krew 플러그인:  kubectl krew install ctx ns neat tree"
