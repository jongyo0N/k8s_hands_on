#!/usr/bin/env bash
# Phase 8 / lab 4 — 공급망 보안: 이미지 스캔 + 서명 검증 게이트 (방어)
# 목표: (1) 배포 전 취약점 스캔으로 걸러내고 (2) 서명된 이미지만 클러스터에 허용한다.
# 실행: bash scripts/04-supply-chain.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="phase-08"
POLICY="${SCRIPT_DIR}/../manifests/04-supply-chain/kyverno-verify-images.yaml"

echo "==> 1) 이미지 취약점 스캔 게이트 (trivy) — HIGH/CRITICAL 발견 시 실패 처리"
if command -v trivy >/dev/null 2>&1; then
  # --exit-code 1 : 심각 취약점이 있으면 비정상 종료 → CI 게이트로 쓰는 패턴
  trivy image --severity HIGH,CRITICAL --exit-code 1 --quiet nginx:1.27-alpine \
    && echo "    통과(심각 취약점 없음)" \
    || echo "    <-- 심각 취약점 발견. CI라면 여기서 빌드를 멈춘다."
else
  echo "    trivy 미설치 — 설치: brew install trivy. (이 단계는 CI 파이프라인 게이트의 축소판)"
fi

echo
echo "==> 2) 서명/검증 개념 (cosign)"
cat <<'EOF'
    # 이미지에 서명(키리스 서명 예):
    #   cosign sign <registry>/<image>@sha256:<digest>
    # 서명 검증:
    #   cosign verify --certificate-identity-regexp '.*' \
    #     --certificate-oidc-issuer-regexp '.*' <image>
    핵심: 태그는 움직인다 → 반드시 '다이제스트'에 서명/검증한다.
EOF

echo
echo "==> 3) 클러스터 게이트: 미서명 이미지 배포 차단 (Kyverno verifyImages)"
echo "    (전제: Kyverno 설치됨 — helm repo add kyverno https://kyverno.github.io/kyverno/)"
kubectl --context "$CTX" apply -f "$POLICY" 2>/dev/null \
  && echo "    정책 적용됨: $(basename "$POLICY")" \
  || echo "    <-- Kyverno 미설치 또는 적용 실패. 정책 파일만 확인: $POLICY"

cat <<'EOF'

    [확인 방법]
    - 정책에 명시된 신뢰 레지스트리/공개키로 '서명된' 이미지는 통과,
      서명 없는 이미지는 admission 단계에서 거부되는지 테스트 Pod로 확인.
    - 운영 팁: 처음엔 Audit 모드(validationFailureAction: Audit)로 관찰 →
      위반이 없어지면 Enforce로 승격(개발 마찰 최소화).
EOF
