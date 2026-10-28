#!/usr/bin/env bash
# Phase 2 / lab 4 — Job podFailurePolicy: exit code로 "재시도 vs 즉시 포기" 분기
# 실행: bash phase-02-workloads/scripts/04-job-podfailurepolicy.sh
#
# 주의: -e를 켜지 않는다. Job이 "일부러 실패"하는 관찰 랩이다.
# 전제: podFailurePolicy는 Kubernetes 1.31+ GA (Phase 0 kind 이미지 v1.33 기준 기본 활성).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="phase-02"
M="${SCRIPT_DIR}/../manifests/04-job-podfailurepolicy"

job_conditions() {  # $1 = job 이름 — 모든 condition을 한 줄씩 출력
  kubectl --context "${CTX}" -n "${NS}" get job "$1" \
    -o jsonpath='{range .status.conditions[*]}    - {.type}={.status} reason={.reason}{"\n"}{end}' 2>/dev/null
  echo
}

echo "==> 0) 네임스페이스 보장"
kubectl --context "${CTX}" apply -f "${SCRIPT_DIR}/../manifests/00-namespace.yaml" >/dev/null

echo
echo "########## CASE A: 영구 오류(exit 42) → FailJob 규칙으로 즉시 포기 ##########"
kubectl --context "${CTX}" -n "${NS}" delete job pfp-fatal --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/job-fatal-exit.yaml"

echo
echo "==> A-1) Job 종료 대기 (즉시 Failed 되어야 정상)"
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Failed job/pfp-fatal --timeout=60s 2>/dev/null || true

echo
echo "==> A-2) 생성된 Pod — 1개여야 한다 (재시도 없음)"
kubectl --context "${CTX}" -n "${NS}" get pods -l case=fatal \
  -o 'custom-columns=POD:.metadata.name,PHASE:.status.phase,EXIT:.status.containerStatuses[0].state.terminated.exitCode' 2>/dev/null || true
echo "    Pod 개수: $(kubectl --context "${CTX}" -n "${NS}" get pods -l case=fatal --no-headers 2>/dev/null | grep -c . || true)"

echo
echo "==> A-3) Job conditions (FailJob으로 중단됐는지 — reason: PodFailurePolicy)"
job_conditions pfp-fatal

echo
echo "########## CASE B: 일시 오류(exit 1) → 규칙 미해당 → backoffLimit까지 재시도 ##########"
kubectl --context "${CTX}" -n "${NS}" delete job pfp-retryable --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/job-retryable-exit.yaml"

echo
echo "==> B-1) Job 종료 대기 (재시도 3회 후 BackoffLimitExceeded로 Failed)"
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Failed job/pfp-retryable --timeout=120s 2>/dev/null || true

echo
echo "==> B-2) 생성된 Pod — 4개여야 한다 (최초 1 + 재시도 3)"
kubectl --context "${CTX}" -n "${NS}" get pods -l case=retryable \
  -o 'custom-columns=POD:.metadata.name,PHASE:.status.phase,EXIT:.status.containerStatuses[0].state.terminated.exitCode' 2>/dev/null || true
echo "    Pod 개수: $(kubectl --context "${CTX}" -n "${NS}" get pods -l case=retryable --no-headers 2>/dev/null | grep -c . || true)"

echo
echo "==> B-3) Job conditions (reason: BackoffLimitExceeded)"
job_conditions pfp-retryable

echo
cat <<'EOF'
==> 해석
    두 Job의 podFailurePolicy는 완전히 동일하다. 다른 것은 컨테이너 exit code뿐:
      - exit 42 → FailJob 규칙에 걸림   → backoffLimit 무시하고 Pod 1개로 즉시 종료.
      - exit 1  → 어떤 규칙에도 안 걸림 → 기본 action=Count → backoffLimit(3)까지 재시도(Pod 4개).
    실무 포인트:
      - "다시 돌려도 똑같이 실패할 오류"(잘못된 입력·설정, 코드 버그)는 FailJob으로 빨리 포기 →
        재시도 예산/클러스터 자원 낭비를 막고, 실패 알림이 빨리 뜬다.
      - 노드 drain/선점 같은 인프라 교란은 onPodConditions: DisruptionTarget → Ignore 로
        backoffLimit을 소모하지 않고 "공짜 재시도" → 애플리케이션 실패와 구분된다.
EOF

echo
echo "정리: kubectl --context ${CTX} -n ${NS} delete -f ${M}"
echo "끝났으면 전체 정리: bash phase-02-workloads/scripts/99-cleanup.sh"
