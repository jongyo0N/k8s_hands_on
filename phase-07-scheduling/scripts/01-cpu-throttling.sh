#!/usr/bin/env bash
# Phase 7 / lab 1 — CPU throttling 관찰 (CFS quota)
# 질문: CPU limit을 빡빡하게 걸면 커널은 프로세스를 어떻게 "느리게" 만드는가?
# 실행: bash phase-07-scheduling/scripts/01-cpu-throttling.sh
#
# 주의: -e를 켜지 않는다(관찰 랩). 실패해도 echo로 남기고 계속 진행한다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
NS="phase-07"
WARMUP="${WARMUP:-15}"   # busy-loop이 throttle을 쌓을 시간(초). 늘리면 수치가 또렷해진다.

# cpu.stat 읽기: cgroup v2 경로 우선, 안 되면 v1 경로로 폴백.
#   v2: /sys/fs/cgroup/cpu.stat        (throttled_usec, 마이크로초)
#   v1: /sys/fs/cgroup/cpu/cpu.stat    (throttled_time, 나노초)
read_cpu_stat() {
  kubectl --context "${CTX}" -n "${NS}" exec "$1" -- \
    sh -c 'cat /sys/fs/cgroup/cpu.stat 2>/dev/null || cat /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null' \
    || echo "    (cpu.stat 읽기 실패)"
}
# nr_throttled / nr_periods 비율(%)을 뽑아 "얼마나 자주 멈췄나"를 한 줄로.
throttle_ratio() {
  awk '/nr_periods/{p=$2} /nr_throttled/{t=$2} END{ if(p>0) printf "    throttle 비율: %d/%d periods = %.1f%%\n", t, p, (t/p)*100; else print "    (periods=0)"}'
}

echo "==> 0) 네임스페이스 준비"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-namespace.yaml" || true

echo
echo "==> 1) 빡빡한 CPU limit(100m) Pod 배포: cpu-throttled"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-cpu-throttled.yaml" || true
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Ready pod/cpu-throttled --timeout=60s || true

echo
echo "==> 2) busy-loop이 throttle을 쌓도록 ${WARMUP}초 대기..."
sleep "${WARMUP}"

echo
echo "==> 3) cpu-throttled 의 cgroup cpu.stat (limit=100m):"
STAT_THROTTLED="$(read_cpu_stat cpu-throttled)"
echo "${STAT_THROTTLED}"
echo "${STAT_THROTTLED}" | throttle_ratio
echo "    해석: nr_throttled 가 nr_periods 에 근접 = 거의 매 period마다 quota 소진 후 멈춤."
echo "          throttled_usec(또는 throttled_time)이 크게 누적된다 = 그만큼 '대기'당한 시간."

echo
echo "    (참고) cadvisor 메트릭으로도 같은 값을 본다 — metrics 파이프라인이 있다면:"
echo "      container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total"
echo "      container_cpu_cfs_throttled_seconds_total"

echo
echo "==> 4) 비교군 배포: cpu-relaxed (같은 busy-loop, limit만 1000m 로 상향)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-cpu-relaxed.yaml" || true
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Ready pod/cpu-relaxed --timeout=60s || true
echo "    ${WARMUP}초 대기..."
sleep "${WARMUP}"

echo
echo "==> 5) cpu-relaxed 의 cgroup cpu.stat (limit=1000m):"
STAT_RELAXED="$(read_cpu_stat cpu-relaxed)"
echo "${STAT_RELAXED}"
echo "${STAT_RELAXED}" | throttle_ratio
echo "    해석: 원하는 만큼(≈1코어) 쓸 수 있으니 throttle이 거의 0에 수렴."

echo
echo "==> 6) 실제 CPU 사용량 대조 (metrics-server가 있으면 숫자가 보인다):"
kubectl --context "${CTX}" -n "${NS}" top pod -l app=cpu-demo 2>/dev/null \
  || echo "    (metrics-server 미설치 — lab 4의 04-metrics-server-install.sh 후 재시도)"

cat <<'EOF'

정리:
  - CPU는 compressible: limit 초과분을 "죽이지 않고" CFS quota로 멈춰 세운다(throttling).
    throttle된 만큼 레이턴시(p99)가 늘어난다 — CrashLoop가 아니라 "느려짐"으로 나타난다.
  - 그래서 "CPU limit을 걸지 말라"는 논쟁이 있다. requests(=cgroup 가중치)만 두면
    경합 시 최소 몫은 보장하면서 throttling 레이턴시는 피한다. 비용은 noisy neighbor.
  - 대비: memory limit 초과는 "못 줄이니 죽인다" → lab 2(OOMKilled).

다음: bash phase-07-scheduling/scripts/02-oom-and-qos.sh
정리(리소스 삭제): bash phase-07-scheduling/scripts/99-cleanup.sh
EOF
