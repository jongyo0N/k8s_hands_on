#!/usr/bin/env bash
# Phase 3 / lab 3 — readiness 실패가 EndpointSlice에서 어떻게 빠지는가 (관찰/실패유도)
# 질문: Pod 하나의 readinessProbe를 일부러 실패시키면 Service 뒤 엔드포인트는 어떻게 되나?
# 실행: bash phase-03-services/scripts/03-endpointslice-readiness.sh
#
# 의도된 실패(파일 삭제로 probe 탈락)를 다루므로 -e 미사용. (관찰: set -uo + || true)
set -uo pipefail

CTX="kind-k8s-mastery"
NS="phase-03"
SVC="readiness-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"

# EndpointSlice를 한 줄로 보기 좋게: 주소 목록과 ready 플래그를 나란히.
SLICE_COLS='SLICE:.metadata.name,ADDRS:.endpoints[*].addresses,READY:.endpoints[*].conditions.ready'

echo "==> 0) readinessProbe가 /tmp/ready 파일 존재를 검사하는 nginx x3 배포"
kubectl --context "$CTX" apply -f "${MANIFESTS}/00-namespace.yaml"
kubectl --context "$CTX" apply -f "${MANIFESTS}/03-readiness.yaml"
kubectl --context "$CTX" -n "$NS" rollout status deployment/readiness-demo --timeout=120s

echo
echo "==> 1) 정상 상태: Pod 3개 모두 Ready, EndpointSlice에 3개 ready=true"
kubectl --context "$CTX" -n "$NS" get pods -l app=readiness-demo -o wide
echo
kubectl --context "$CTX" -n "$NS" get endpointslices -l "kubernetes.io/service-name=${SVC}" \
  -o custom-columns="$SLICE_COLS"

echo
echo "==> 2) 희생양 Pod 하나 선택"
VICTIM="$(kubectl --context "$CTX" -n "$NS" get pods -l app=readiness-demo \
  -o jsonpath='{.items[0].metadata.name}')"
echo "    victim = ${VICTIM:-(못 찾음)}"

echo
echo "==> 3) 그 Pod의 readiness를 '일부러' 실패: /tmp/ready 파일 삭제"
echo "    (probe = exec[cat /tmp/ready], period=2s / failureThreshold=2 -> 약 4초 뒤 NotReady)"
if kubectl --context "$CTX" -n "$NS" exec "$VICTIM" -- rm -f /tmp/ready; then
  echo "    -> 삭제 완료. 곧 readinessProbe가 실패한다."
else
  echo "    (삭제 실패 — victim 이름/상태 확인)"
fi

echo
echo "==> 4) 전파 관찰: victim의 컨테이너 Ready가 true->false 로, EndpointSlice에서 ready=false 로"
for i in $(seq 1 8); do
  echo "--- t≈$((i*2))s ---"
  kubectl --context "$CTX" -n "$NS" get pod "$VICTIM" \
    -o custom-columns='POD:.metadata.name,CONTAINER_READY:.status.containerStatuses[*].ready,PHASE:.status.phase' \
    --no-headers 2>/dev/null || true
  kubectl --context "$CTX" -n "$NS" get endpointslices -l "kubernetes.io/service-name=${SVC}" \
    -o custom-columns="$SLICE_COLS" --no-headers 2>/dev/null || true
  sleep 2
done

echo
echo "==> 5) EndpointSlice 상세: victim 주소는 '남아있되' conditions.ready=false (제외됨, 삭제 아님)"
kubectl --context "$CTX" -n "$NS" get endpointslices -l "kubernetes.io/service-name=${SVC}" -o yaml \
  | grep -E 'addresses:|- [0-9]|ready:|serving:|terminating:|nodeName:|targetRef:' | head -n 60 || true
echo
echo "    (legacy Endpoints API 관점 — ready 주소 vs notReadyAddresses 로 분리되어 보인다)"
kubectl --context "$CTX" -n "$NS" get endpoints "$SVC" -o wide 2>/dev/null || true

echo
echo "==> 6) 원복: /tmp/ready 를 다시 만들면 몇 초 뒤 다시 Ready & 엔드포인트 복귀"
kubectl --context "$CTX" -n "$NS" exec "$VICTIM" -- touch /tmp/ready \
  && echo "    -> 복구 트리거. 잠시 대기..." || true
sleep 6
kubectl --context "$CTX" -n "$NS" get endpointslices -l "kubernetes.io/service-name=${SVC}" \
  -o custom-columns="$SLICE_COLS"

cat <<'EOF'

    해석:
      readinessProbe 실패
        -> kubelet이 Pod의 Ready 컨디션을 false 로
        -> EndpointSlice 컨트롤러가 그 endpoint의 conditions.ready=false 로 갱신
        -> kube-proxy가 해당 KUBE-SEP-* 를 KUBE-SVC-* 분배에서 제외
        -> 트래픽이 그 Pod로 가지 않는다.
      중요: Ready=false 는 '삭제'가 아니다. Pod는 Running이고 주소도 슬라이스에 남는다.
            단지 '서빙 대상'에서만 빠진다. (graceful 종료 시의 serving/terminating 플래그와 구분)
      이 메커니즘이 롤링 업데이트/워밍업 중 "준비 안 된 Pod로 트래픽이 가지 않게" 막아준다.

    생각해볼 질문(NOTES.md):
      - readiness 와 liveness 의 역할 차이는? (트래픽 제외 vs 재시작)
      - EndpointSlice 가 (옛) Endpoints 를 대체한 이유는? (대규모에서의 watch/업데이트 비용)

다음: bash phase-03-services/scripts/04-external-traffic-policy.sh
EOF
