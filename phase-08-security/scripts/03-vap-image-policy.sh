#!/usr/bin/env bash
# Phase 8 / lab 3 — ValidatingAdmissionPolicy(CEL) 적용 & 위반 거부 검증
# 실행: bash phase-08-security/scripts/03-vap-image-policy.sh
#
# 흐름: VAP(이미지 출처 + :latest 금지) 적용 → 위반 이미지가 '거부'되고,
#       규칙을 만족하는 이미지는 '통과'함을 --dry-run=server(실제 생성 없이 admission만)로 검증.
#
# 테스트 Pod는 'restricted PSA도 통과'하도록 하드닝돼 있다(lab 1). 그래서 거부/통과의
# 판정 주체가 오직 VAP임이 보장된다 — 계층 통제(PSA+VAP)가 함께 걸려 있음을 보여준다.
#
# 주의: -e를 켜지 않는다. "일부러 거부되는" dry-run이 있기 때문(정상 동작).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
M="${SCRIPT_DIR}/../manifests/03-vap"
K="kubectl --context ${CTX}"

echo "==> 0) 전제: phase-08 네임스페이스 존재(없으면 lab 1 먼저)"
${K} get ns phase-08 >/dev/null 2>&1 || { echo "    phase-08 없음 → 01-psa-restricted.sh 먼저 실행"; exit 1; }

echo "==> 1) ValidatingAdmissionPolicy + Binding 적용"
${K} apply -f "${M}/validating-admission-policy.yaml"
echo "    (정책 등록 후 집행까지 수 초 걸릴 수 있음)"
echo

# 하드닝 Pod를 템플릿해 이미지만 바꿔 admission 판정을 받는다.
try_image() {
  local name="$1" image="$2" expect="$3"
  local tmp out
  tmp="$(mktemp)"
  cat > "${tmp}" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  namespace: phase-08
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: c
      image: ${image}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
EOF
  echo "    --- ${name}: image=${image}  (기대: ${expect}) ---"
  if out="$(${K} apply --dry-run=server -f "${tmp}" 2>&1)"; then
    echo "    => 통과(allowed)"
  else
    echo "    => 거부(denied):"
    echo "${out}" | grep -iE 'denied|forbidden|레지스트리|latest|다이제스트' | head -2 | sed 's/^/        /'
  fi
  rm -f "${tmp}"
  echo
}

echo "==> 2) 규칙 위반 이미지는 거부되는가? (모두 denied 기대)"
try_image deny-registry "docker.io/library/busybox:1.37"  denied   # (a) 미승인 레지스트리
try_image deny-latest   "ghcr.io/jongyo0N/app:latest"     denied   # (b) :latest 금지
try_image deny-notag    "ghcr.io/jongyo0N/app"            denied   # (b) 태그 미지정

echo "==> 3) 규칙을 만족하는 이미지는 통과하는가? (모두 allowed 기대)"
try_image allow-pause   "registry.k8s.io/pause:3.10"       allowed  # 승인 prefix + 고정 태그
try_image allow-ghcr    "ghcr.io/jongyo0N/app:1.0.0"       allowed  # 승인 prefix + 고정 태그

cat <<'EOF'
    핵심 정리:
      - VAP/CEL은 '구조' 규칙(출처 prefix, 태그 형태)에 강하고, 외부 I/O·암호 검증(서명)은 못 한다.
        → 서명 검증은 lab 4의 Kyverno로.
      - 단계적 도입: Binding의 validationActions를 ["Audit","Warn"]로 먼저 → ["Deny"]로 승격.
      - 컨트롤러 주의: Deployment에 위반 이미지를 넣으면 'Pod' 생성이 거부된다.
        상위 Deployment는 Accepted로 남고 ReplicaSet 이벤트에 에러가 쌓인다
        (kubectl -n phase-08 describe rs <name> 으로 확인).

다음: bash phase-08-security/scripts/04-supply-chain-gate.sh
EOF
