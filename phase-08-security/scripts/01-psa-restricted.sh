#!/usr/bin/env bash
# Phase 8 / lab 1 — Pod Security Admission(restricted) 적용 & 하드닝 검증
# 실행: bash phase-08-security/scripts/01-psa-restricted.sh
#
# 흐름: restricted 네임스페이스 생성 → 하드닝 안 된 Pod가 '거부'됨을 확인 →
#       securityContext를 채운 Pod가 '통과'함을 확인.
#
# 주의: -e를 켜지 않는다. 중간에 "일부러 거부되는" apply가 있기 때문(정상 동작).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
M="${SCRIPT_DIR}/../manifests/01-psa"
K="kubectl --context ${CTX}"

echo "==> 1) restricted PSA 라벨이 붙은 phase-08 네임스페이스 생성"
${K} apply -f "${M}/namespace.yaml"
echo
echo "    적용된 PSA 라벨:"
${K} get ns phase-08 -o jsonpath='{.metadata.labels}' | tr ',' '\n' | grep pod-security || true
echo

echo "==> 2) [BEFORE] 하드닝 안 된 Pod 생성 시도 (거부되는 것이 '정상')"
echo "    \$ kubectl apply -f pod-insecure.yaml"
${K} apply -f "${M}/pod-insecure.yaml" || echo "    <-- 예상대로 restricted가 거부함. 거부 사유(violates PodSecurity ...)를 읽어볼 것."
echo

echo "==> 3) [AFTER] securityContext를 채운 Pod 생성 (통과해야 정상)"
${K} apply -f "${M}/pod-hardened.yaml"
echo "    Ready 대기..."
${K} wait --for=condition=Ready pod/web-hardened -n phase-08 --timeout=90s \
  || echo "    (이미지 pull/기동 지연일 수 있음 — 'kubectl -n phase-08 describe pod web-hardened'로 확인)"
echo

echo "==> 4) 결과 확인: insecure는 없고 hardened만 떠야 한다"
${K} get pods -n phase-08 -l app=web -o wide

cat <<'EOF'

    핵심 정리:
      - restricted는 "좋은 이미지"가 아니라 "명시된 securityContext"를 요구한다.
      - before/after의 차이(runAsNonRoot, allowPrivilegeEscalation:false,
        capabilities drop ALL, seccompProfile RuntimeDefault, readOnlyRootFilesystem)가
        곧 restricted가 요구하는 하드닝의 전부다.
      - readOnlyRootFilesystem는 restricted의 '필수'는 아니지만, 켜면 앱이 쓰던 경로에
        emptyDir를 따로 줘야 한다(방어심화의 현실적 비용).

다음: bash phase-08-security/scripts/02-rbac-audit.sh
EOF
