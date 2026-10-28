#!/usr/bin/env bash
# Phase 8 / lab 2 — 최소 권한 RBAC 적용 & 권한 범위 감사
# 실행: bash phase-08-security/scripts/02-rbac-audit.sh
#
# 흐름: SA/Role/RoleBinding 적용 → `kubectl auth can-i --list --as=<SA>`로 '부여된' 권한을
#       나열 → 과잉 권한(secrets 읽기, 쓰기 verb, 와일드카드, 클러스터 범위)이 '없음'을 검증.
#
# set -e 유지 가능: can-i 의 성공/실패는 모두 'if' 조건에서 받으므로 스크립트가 중단되지 않는다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="phase-08"
SA="system:serviceaccount:${NS}:appsa"
M="${SCRIPT_DIR}/../manifests/02-rbac"
K="kubectl --context ${CTX}"

echo "==> 1) ServiceAccount / Role / RoleBinding 적용"
${K} apply -f "${M}/serviceaccount.yaml"
${K} apply -f "${M}/role.yaml"
${K} apply -f "${M}/rolebinding.yaml"
echo

echo "==> 2) appsa에 '부여된' 권한 전체 나열 (--as 임퍼소네이션으로 감사)"
echo "    \$ kubectl auth can-i --list --as=${SA} -n ${NS}"
${K} auth can-i --list --as="${SA}" -n "${NS}"
echo

# 헬퍼: 특정 동작이 기대(yes/no)와 일치하는지 검사
#   expect=no  → 과잉 권한이 '없어야' 하는 항목 (핵심 감사)
#   expect=yes → 앱이 '필요로 하는' 최소 권한 항목
check() {
  local expect="$1"; shift
  local desc="$1"; shift
  local verdict
  if ${K} auth can-i "$@" --as="${SA}" -n "${NS}" >/dev/null 2>&1; then
    verdict="yes"
  else
    verdict="no"
  fi
  if [[ "${verdict}" == "${expect}" ]]; then
    echo "    [OK]   ${desc} → ${verdict} (기대: ${expect})"
  else
    echo "    [WARN] ${desc} → ${verdict} (기대: ${expect})  <-- 재검토 필요"
  fi
}

echo "==> 3) 과잉 권한이 '없음'을 검증 (모두 no 여야 함)"
check no  "secrets 읽기(get secrets)"            get    secrets
check no  "secrets 전체(list secrets)"           list   secrets
check no  "pods 생성(create pods)"               create pods
check no  "pods 삭제(delete pods)"               delete pods
check no  "pods 수정(patch pods)"                patch  pods
check no  "모든 동작/모든 리소스('*' '*')"       '*'    '*'
check no  "클러스터 범위(get nodes)"             get    nodes
check no  "RBAC 상승(create rolebindings)"       create rolebindings.rbac.authorization.k8s.io
echo

echo "==> 4) '필요한' 최소 권한은 있는지 확인 (모두 yes 여야 함)"
check yes "pods 조회(get pods)"                  get    pods
check yes "pods 목록(list pods)"                 list   pods
check yes "configmaps 조회(get configmaps)"      get    configmaps
echo

echo "==> 5) (보너스) 위험 verb를 가진 바인딩 탐지 — 클러스터 전역 점검 감 잡기"
echo "    escalate/bind/impersonate 를 부여하는 ClusterRole 목록:"
${K} get clusterroles -o json \
  | jq -r '.items[] | select(.rules[]? | (.verbs // []) | any(. == "escalate" or . == "bind" or . == "impersonate" or . == "*")) | .metadata.name' \
  | sort -u | sed 's/^/      /' || true

cat <<'EOF'

    핵심 정리:
      - 감사 = "무엇을 줬나"가 아니라 "무엇까지 되나"를 --as 로 '실측'하는 것.
      - 과잉 권한의 단골: secrets 읽기, 와일드카드(*), 불필요한 ClusterRoleBinding,
        escalate/bind/impersonate 같은 권한 상승 verb.
      - 감사 후에는 "쓰지 않는 ClusterRoleBinding부터 제거"가 가장 효과 큰 정리.

다음: bash phase-08-security/scripts/03-vap-image-policy.sh
EOF
