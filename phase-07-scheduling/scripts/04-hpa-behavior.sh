#!/usr/bin/env bash
# Phase 7 / lab 4 — HPA behavior 튜닝으로 플래핑 방지
# 질문: 트래픽이 출렁일 때 replica가 급등락(플래핑)하지 않게 하려면?
# 실행: bash phase-07-scheduling/scripts/04-hpa-behavior.sh
# 사전: 04-metrics-server-install.sh 를 먼저 실행해 둘 것.
#
# 주의: -e를 켜지 않는다(관찰 랩).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
NS="phase-07"
UP_SECONDS="${UP_SECONDS:-120}"    # 부하 주며 scale-up 관찰할 시간(초)
HOLD_SECONDS="${HOLD_SECONDS:-60}" # 부하 제거 후 "안 줄어드는지"(stabilization) 볼 시간(초)

# HPA 현재 상태를 한 줄로 (컬럼 파싱 대신 jsonpath — 견고함)
hpa_line() {
  local util cur des
  util="$(kubectl --context "${CTX}" -n "${NS}" get hpa php-apache \
    -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)"
  cur="$(kubectl --context "${CTX}" -n "${NS}" get hpa php-apache \
    -o jsonpath='{.status.currentReplicas}' 2>/dev/null)"
  des="$(kubectl --context "${CTX}" -n "${NS}" get hpa php-apache \
    -o jsonpath='{.status.desiredReplicas}' 2>/dev/null)"
  echo "cpu=${util:-?}%/target50%  currentReplicas=${cur:-?} desiredReplicas=${des:-?}"
}

echo "==> 0) 전제 확인: metrics-server 가 값을 주는가?"
if ! kubectl --context "${CTX}" top nodes >/dev/null 2>&1; then
  echo "    metrics API 미준비. 먼저: bash phase-07-scheduling/scripts/04-metrics-server-install.sh"
  echo "    (설치돼 있어도 수집까지 수십 초 걸릴 수 있으니 잠시 후 재시도)"
  exit 0
fi
echo "    OK."
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-namespace.yaml" || true

echo
echo "==> 1) 대상 앱 배포: php-apache (요청마다 CPU를 태우는 앱)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/04-php-apache.yaml" || true
kubectl --context "${CTX}" -n "${NS}" rollout status deployment/php-apache --timeout=120s || true

echo
echo "==> 2) HPA(autoscaling/v2, behavior 포함) 적용"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/04-hpa.yaml" || true
sleep 5
echo "    초기 HPA 상태: $(hpa_line)"

echo
echo "==> 3) 부하 생성기 투입 (busybox에서 Service로 wget 루프 3개 동시)"
kubectl --context "${CTX}" -n "${NS}" delete pod load-generator --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "${CTX}" -n "${NS}" run load-generator --image=busybox:1.37 --restart=Never -- \
  /bin/sh -c 'for i in 1 2 3; do (while true; do wget -q -O- http://php-apache >/dev/null 2>&1; done) & done; wait' \
  || echo "    (부하 생성기 기동 실패)"

echo
echo "==> 4) scale-up 관찰 (${UP_SECONDS}초): scaleUp.stabilizationWindow=0 이라 빠르게 오른다"
echo "    현재 CPU%가 타겟(50%)을 넘으면 desiredReplicas 가 증가한다."
end=$((SECONDS + UP_SECONDS))
while [ "${SECONDS}" -lt "${end}" ]; do
  echo "    [t+$((UP_SECONDS - (end - SECONDS)))s] $(hpa_line)"
  sleep 15
done
echo
echo "    현재 Pod 목록:"
kubectl --context "${CTX}" -n "${NS}" get pods -l app=php-apache -o wide 2>/dev/null || true

echo
echo "==> 5) 부하 제거"
kubectl --context "${CTX}" -n "${NS}" delete pod load-generator --ignore-not-found || true

echo
echo "==> 6) scale-down 관찰 (${HOLD_SECONDS}초): scaleDown.stabilizationWindow=300 이라"
echo "    부하가 빠져도 '바로' 줄지 않는다 — 이게 플래핑 방지의 핵심."
end=$((SECONDS + HOLD_SECONDS))
while [ "${SECONDS}" -lt "${end}" ]; do
  echo "    [hold +$((HOLD_SECONDS - (end - SECONDS)))s] $(hpa_line)"
  sleep 15
done

cat <<'EOF'

    → replica 가 아직 안 줄었을 것이다(정상). 300초 안정화 윈도우가 "최근 5분 중
      가장 높았던 추천치"를 채택하기 때문. 완전 축소까지 지켜보려면:
        kubectl --context kind-k8s-mastery -n phase-07 get hpa php-apache -w
      behavior 가 적용된 근거(이벤트)를 보려면:
        kubectl --context kind-k8s-mastery -n phase-07 describe hpa php-apache

정리:
  - HPA 루프: metrics-server 수집(kubelet/cAdvisor) → utilization 계산 →
    desiredReplicas=ceil(cur*(curUtil/target)) → 스케일. 기본 15초 주기 + 수집 지연이
    곧 '반응 지연'이다.
  - behavior 로 비대칭 정책: 올릴 땐 window=0(즉시), 내릴 땐 window=300s(관성) →
    스파이크엔 민첩, 잔물결엔 둔감 = 플래핑 억제.
  - ⚖️ HPA vs VPA 동시 사용은 같은 CPU 메트릭을 두고 충돌한다. VPA는 '추천값' 소스로만
    쓰거나 in-place resize(1.33+)로 재시작 비용을 줄이는 운영이 보수적 정답.

다음: bash phase-07-scheduling/scripts/05-keda-install.sh   # (선택) 이벤트 기반 0 스케일
정리(리소스 삭제): bash phase-07-scheduling/scripts/99-cleanup.sh
EOF
