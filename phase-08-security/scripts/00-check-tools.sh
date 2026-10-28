#!/usr/bin/env bash
# Phase 8 / lab 0 — 보안 랩 도구 점검
# 실행: bash phase-08-security/scripts/00-check-tools.sh
#
# 전제: Phase 0에서 만든 kind 클러스터(context: kind-k8s-mastery)가 떠 있어야 한다.
set -uo pipefail

CTX="kind-k8s-mastery"

echo "==> 필수 도구 (Phase 8 랩 전반)"
for t in kubectl docker jq openssl; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t  ($(command -v "$t"))"
  else
    echo "  [MISS] $t  <-- 설치 필요"
  fi
done

echo
echo "==> 공급망 랩(lab 4)용 도구"
for t in trivy cosign helm; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  [ok]   $t"
  else
    echo "  [--]   $t  (lab 4에서 사용 — 없으면 해당 단계는 안내만 출력)"
  fi
done

echo
echo "==> 클러스터 연결 확인 (context: ${CTX})"
if kubectl --context "${CTX}" version -o json >/dev/null 2>&1; then
  echo "  [ok]   ${CTX} 연결됨"
  echo "  서버 버전: $(kubectl --context "${CTX}" version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"')"
  echo
  echo "  ValidatingAdmissionPolicy(lab 3)는 1.30+ 에서 GA. 현재 버전 확인:"
  if kubectl --context "${CTX}" api-resources --api-group=admissionregistration.k8s.io 2>/dev/null | grep -q validatingadmissionpolicies; then
    echo "    [ok] validatingadmissionpolicies 리소스 사용 가능"
  else
    echo "    [--] validatingadmissionpolicies 미노출 — 클러스터 버전/피처게이트 확인 필요"
  fi
else
  echo "  [MISS] ${CTX} 에 연결 불가 — Phase 0의 01-create-cluster.sh로 클러스터를 먼저 띄울 것"
fi

echo
echo "버전 핀(2026-10 기준, 최신 확인 권장):"
echo "  trivy   v0.72.x   https://github.com/aquasecurity/trivy/releases"
echo "  cosign  v3.x      https://github.com/sigstore/cosign/releases  (3.0부터 번들 기본값 변경)"
echo "  kyverno v1.16.x   https://github.com/kyverno/kyverno/releases  (k8s 호환 매트릭스 확인)"
echo
echo "macOS(Homebrew) 설치 힌트:"
echo "  brew install trivy cosign kyverno helm jq"
