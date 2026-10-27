#!/usr/bin/env bash
# Phase 2 / lab 2 — 부하 중 rolling update에서 5xx(및 커넥션 거부) 0 달성
# 실행: bash phase-02-workloads/scripts/02-rolling-update.sh
#
# 성공 데모지만 부하 생성기 로그 수집 등 관찰 명령이 많아, 그 부분은 || true로 가드한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="phase-02"
M="${SCRIPT_DIR}/../manifests/02-rolling-update"

echo "==> 0) 네임스페이스 보장"
kubectl --context "${CTX}" apply -f "${SCRIPT_DIR}/../manifests/00-namespace.yaml" >/dev/null

echo
echo "==> 1) Deployment(replicas=4) + Service 배포 후 Ready 대기"
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/deployment.yaml"
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/service.yaml"
kubectl --context "${CTX}" -n "${NS}" rollout status deployment/rolling-web --timeout=120s

echo
echo "==> 2) 부하 생성기 기동 — Service로 0.1초 간격 요청, 200이 아니면 실패(BAD)로 집계"
echo "    (code=000 커넥션 실패/타임아웃, code=5xx 서버 오류)"
kubectl --context "${CTX}" -n "${NS}" delete pod loadgen --ignore-not-found >/dev/null || true
kubectl --context "${CTX}" -n "${NS}" run loadgen --image=curlimages/curl:8.11.1 --restart=Never --command -- \
  /bin/sh -c '
    i=0; fail=0;
    while true; do
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://rolling-svc.phase-02.svc.cluster.local/ || echo 000);
      i=$((i+1));
      if [ "$code" != "200" ]; then
        fail=$((fail+1));
        echo "[$(date +%T)] BAD code=$code (누적 실패 $fail / 요청 $i)";
      fi;
      sleep 0.1;
    done'
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Ready pod/loadgen --timeout=60s

echo
echo "==> 3) 베이스라인 5초 수집 (정상이면 이 구간 실패 0)"
sleep 5

echo
echo "==> 4) rolling update 트리거 (rollout restart → 새 ReplicaSet으로 점진 교체)"
kubectl --context "${CTX}" -n "${NS}" rollout restart deployment/rolling-web
kubectl --context "${CTX}" -n "${NS}" rollout status deployment/rolling-web --timeout=180s

echo
echo "==> 5) 전파 안정화까지 5초 더 수집"
sleep 5

echo
echo "==> 6) 결과 — 부하 생성기 로그의 BAD(실패) 줄을 센다. 0이면 무중단 성공."
kubectl --context "${CTX}" -n "${NS}" logs loadgen 2>/dev/null | grep 'BAD' || echo "    (BAD 줄 없음 — 실패 0)"
bad="$(kubectl --context "${CTX}" -n "${NS}" logs loadgen 2>/dev/null | grep -c 'BAD' || true)"
echo "    => 실패 요청 수: ${bad}"

echo
cat <<'EOF'
==> 해석 (왜 5xx/커넥션 거부가 0인가 — 세 요소의 합작)
    - readinessProbe   : 새 Pod가 Ready여야 엔드포인트에 등록 → 준비 안 된 Pod로 안 보낸다.
    - maxUnavailable=0 / maxSurge=1 : 새 Pod가 Ready된 뒤에야 구 Pod를 내린다 → 항상 4개가 응답.
    - preStop(sleep 10) + terminationGracePeriodSeconds=30 :
        구 Pod가 Terminating이 돼도 바로 안 죽고 버틴다. 그 사이 EndpointSlice에서 제거가
        전파되고 kube-proxy 규칙이 갱신된다(전파는 비동기 → 지연 존재). 덕분에
        "엔드포인트엔 아직 있는데 프로세스는 이미 죽은" 레이스 창이 사라진다.
    셋 중 하나라도 빠지면 롤아웃 순간에 커넥션 거부(000)나 5xx가 샐 수 있다.
EOF

echo
echo "정리: kubectl --context ${CTX} -n ${NS} delete pod loadgen"
echo "      kubectl --context ${CTX} -n ${NS} delete -f ${M}"
echo "다음: bash phase-02-workloads/scripts/03-statefulset.sh"
