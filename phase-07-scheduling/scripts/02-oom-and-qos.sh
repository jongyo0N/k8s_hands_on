#!/usr/bin/env bash
# Phase 7 / lab 2 — OOMKilled & QoS 클래스 관찰
# 질문: memory limit 초과는 왜 "죽음"이고, 노드가 쪼들리면 누가 먼저 쫓겨나는가?
# 실행: bash phase-07-scheduling/scripts/02-oom-and-qos.sh
#
# 주의: -e를 켜지 않는다(관찰 랩). OOM으로 컨테이너가 죽는 게 "정상 시나리오".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
NS="phase-07"

echo "==> 0) 네임스페이스 준비"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-namespace.yaml" || true

echo
echo "==> 1) memory limit(32Mi) 초과 Pod 배포: oom-victim ('tail /dev/zero')"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/02-oom.yaml" || true

echo
echo "==> 2) OOMKilled 가 날 때까지 잠시 대기 (최대 ~40초 폴링)"
for _ in $(seq 1 20); do
  reason="$(kubectl --context "${CTX}" -n "${NS}" get pod oom-victim \
    -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)"
  if [ "${reason}" = "OOMKilled" ]; then break; fi
  sleep 2
done

echo
echo "==> 3) Pod 상태: reason / exit code / 재시작 횟수"
kubectl --context "${CTX}" -n "${NS}" get pod oom-victim -o wide 2>/dev/null || true
echo
echo "    lastState.terminated (여기서 reason=OOMKilled, exitCode=137 을 확인):"
kubectl --context "${CTX}" -n "${NS}" get pod oom-victim \
  -o jsonpath='      reason={.status.containerStatuses[0].lastState.terminated.reason}{"\n"}      exitCode={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}      restartCount={.status.containerStatuses[0].restartCount}{"\n"}' 2>/dev/null || true
echo
echo "    exit code 137 = 128 + 9 → 커널 OOM killer가 보낸 SIGKILL(9). SIGTERM 유예 없음."

echo
echo "==> 4) describe 이벤트에서 OOMKilled / BackOff 흔적:"
kubectl --context "${CTX}" -n "${NS}" describe pod oom-victim 2>/dev/null \
  | grep -E 'OOMKilled|BackOff|Reason|Last State|Exit Code|Restart' \
  || echo "    (아직 이벤트가 안 보이면 잠시 후 kubectl describe 로 재확인)"

echo
echo "==> 5) QoS 3종 배포 (Guaranteed / Burstable / BestEffort)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/02-qos.yaml" || true
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Ready \
  pod/qos-guaranteed pod/qos-burstable pod/qos-besteffort --timeout=60s || true

echo
echo "==> 6) 각 Pod의 status.qosClass (spec에 쓰는 값이 아니라 kubelet이 매긴 결과):"
for p in qos-guaranteed qos-burstable qos-besteffort; do
  q="$(kubectl --context "${CTX}" -n "${NS}" get pod "${p}" -o jsonpath='{.status.qosClass}' 2>/dev/null)"
  echo "    ${p}  ->  qosClass=${q:-?}"
done
echo
echo "    (한눈에 보기)"
kubectl --context "${CTX}" -n "${NS}" get pods -l app=qos-demo \
  -o custom-columns='NAME:.metadata.name,QOS:.status.qosClass' 2>/dev/null || true

cat <<'EOF'

정리:
  - memory는 incompressible: limit 초과 = 회수 불가 → 커널이 SIGKILL(OOMKilled, 137).
    CPU throttling(느려짐)과 달리 "즉사"다. 재시작 반복 시 CrashLoopBackOff로 수렴.
  - QoS는 노드 메모리 압박 시 "축출(eviction) 순서"를 정한다:
      BestEffort(먼저) → Burstable(requests 초과분 큰 순) → Guaranteed(마지막).
    선언(requests/limits)이 곧 보호다. 아무것도 안 쓴 Pod가 가장 먼저 쫓겨난다.
  - cgroup OOM(컨테이너 단위 limit 초과)과 노드 eviction(kubelet의 노드 압박 대응)은
    별개의 메커니즘임에 주의 — 전자는 커널, 후자는 kubelet이 주체다.

다음: bash phase-07-scheduling/scripts/03-node-drain-pdb.sh
정리(리소스 삭제): bash phase-07-scheduling/scripts/99-cleanup.sh
EOF
