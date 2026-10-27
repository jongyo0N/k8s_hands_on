#!/usr/bin/env bash
# Phase 2 / lab 1 — startup probe 없이 liveness만 → CrashLoopBackOff 재현 후 수정
# 실행: bash phase-02-workloads/scripts/01-startup-probe.sh
#
# 주의: -e를 켜지 않는다. "일부러 실패하는" 관찰(CrashLoop 확인)이 중간에 있기 때문.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="phase-02"
M="${SCRIPT_DIR}/../manifests/01-startup-probe"

echo "==> 0) 네임스페이스 보장"
kubectl --context "${CTX}" apply -f "${SCRIPT_DIR}/../manifests/00-namespace.yaml" >/dev/null

echo
echo "==> 1) [BEFORE] startup probe 없이 liveness만 건 Pod 배포 (기동에 20초 걸리는 앱)"
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/before-liveness-only.yaml"

echo
echo "==> 2) 약 60초 관찰 — liveness가 기동(20s) 전에 때려 반복 재시작된다"
echo "    (RESTARTS가 올라가고 STATUS가 CrashLoopBackOff로 가는지 본다)"
for _ in $(seq 1 6); do
  sleep 10
  kubectl --context "${CTX}" -n "${NS}" get pod slow-start-broken \
    -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,REASON:.status.containerStatuses[0].lastState.terminated.reason' \
    2>/dev/null || true
done

echo
echo "    상세 이벤트(원인: Liveness probe failed → Killing 반복):"
kubectl --context "${CTX}" -n "${NS}" describe pod slow-start-broken 2>/dev/null \
  | grep -A20 '^Events:' || true

echo
echo "==> 3) [AFTER] 동일 앱에 startup probe를 추가한 Pod 배포"
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/after-startup-probe.yaml"

echo
echo "==> 4) 약 40초 관찰 — startup probe가 기동 구간을 덮어, 죽지 않고 Ready가 된다"
for _ in $(seq 1 5); do
  sleep 8
  kubectl --context "${CTX}" -n "${NS}" get pod slow-start-fixed \
    -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount' \
    2>/dev/null || true
done

echo
cat <<'EOF'
==> 해석
    BEFORE: liveness는 "살아있나?"를 묻는 probe인데 기동 0초부터 때렸다. 서버는 20초에야
            뜨므로 매번 그 전에 3연속 실패 → kubelet이 컨테이너 재시작 → 또 20초 기동 실패 →
            CrashLoopBackOff(지수 백오프). READY는 끝내 true가 되지 않는다.
    AFTER : startup probe가 "아직 떠보는 중"을 책임진다(여기선 최대 45초 유예). 통과 전까지
            liveness/readiness는 아예 실행되지 않으므로 기동 중에 죽지 않는다. 20초에 뜨면
            startup 성공 → 그때부터 liveness로 전환 → RESTARTS 0으로 Ready.
    교훈  : liveness는 "복구 불가(데드락 등) 상태의 치유"용이지 "느린 기동 감지"용이 아니다.
            느린 기동은 startup probe의 몫. 외부 의존성 체크를 liveness에 넣지 말 것(재시작 폭풍).
EOF

echo
echo "정리: kubectl --context ${CTX} -n ${NS} delete pod slow-start-broken slow-start-fixed"
echo "다음: bash phase-02-workloads/scripts/02-rolling-update.sh"
