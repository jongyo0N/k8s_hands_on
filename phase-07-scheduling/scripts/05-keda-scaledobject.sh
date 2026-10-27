#!/usr/bin/env bash
# Phase 7 / lab 5 (선택) — KEDA ScaledObject (cron 트리거)로 0까지 축소 관찰
# 질문: HPA가 못 하는 "0 스케일"과 이벤트/스케줄 기반 스케일을 KEDA는 어떻게 하나?
# 실행: bash phase-07-scheduling/scripts/05-keda-scaledobject.sh
# 사전: 05-keda-install.sh 를 먼저 실행해 둘 것.
#
# 주의: -e를 켜지 않는다(관찰 랩).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
NS="phase-07"
OBSERVE_SECONDS="${OBSERVE_SECONDS:-450}"  # 0→3→0 전 구간을 보려면 ~7.5분

so_line() {
  local spec ready active
  spec="$(kubectl --context "${CTX}" -n "${NS}" get deploy keda-worker -o jsonpath='{.spec.replicas}' 2>/dev/null)"
  ready="$(kubectl --context "${CTX}" -n "${NS}" get deploy keda-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
  active="$(kubectl --context "${CTX}" -n "${NS}" get scaledobject keda-worker-cron \
    -o jsonpath='{.status.conditions[?(@.type=="Active")].status}' 2>/dev/null)"
  echo "deploy replicas(spec)=${spec:-?} ready=${ready:-0}  ScaledObject.Active=${active:-?}"
}

echo "==> 0) 전제 확인: KEDA CRD 존재?"
if ! kubectl --context "${CTX}" get crd scaledobjects.keda.sh >/dev/null 2>&1; then
  echo "    KEDA 미설치. 먼저: bash phase-07-scheduling/scripts/05-keda-install.sh"
  exit 0
fi
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-namespace.yaml" || true

echo
echo "==> 1) Deployment(keda-worker) + ScaledObject 적용"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/05-scaledobject.yaml" || true

echo
echo "==> 2) 빠른 관찰을 위해 cron 창을 '지금+1분 ~ 지금+6분(UTC)'으로 패치"
if command -v python3 >/dev/null 2>&1; then
  START_CRON="$(python3 -c 'import datetime as d; t=d.datetime.now(d.timezone.utc)+d.timedelta(minutes=1); print(f"{t.minute} {t.hour} * * *")')"
  END_CRON="$(python3 -c 'import datetime as d; t=d.datetime.now(d.timezone.utc)+d.timedelta(minutes=6); print(f"{t.minute} {t.hour} * * *")')"
  echo "    start=\"${START_CRON}\"  end=\"${END_CRON}\"  (timezone Etc/UTC)"
  echo "    (주의: UTC 자정 직전에 실행하면 창이 날짜를 넘겨 예상과 다를 수 있다 — 그땐 몇 분 뒤 재실행)"
  kubectl --context "${CTX}" -n "${NS}" patch scaledobject keda-worker-cron --type=json -p "[
    {\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/start\",\"value\":\"${START_CRON}\"},
    {\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/end\",\"value\":\"${END_CRON}\"}
  ]" || echo "    (패치 실패 — 매니페스트의 기본 창(06~20 UTC)으로 관찰하거나 직접 수정)"
else
  echo "    python3 없음 → 매니페스트 기본 창(06~20 UTC) 그대로 사용."
  echo "    현재 UTC 시간: $(date -u '+%H:%M') — 창 밖이면 0으로, 창 안이면 3으로 수렴한다."
fi

echo
echo "==> 3) 전이 관찰 (${OBSERVE_SECONDS}초): 기대 흐름 = 1 → 0(창 전) → 3(창 안) → 0(창 후)"
echo "    KEDA는 창 밖이면 replicas를 0으로 직접 내리고(cooldown 후), 창 안이면"
echo "    내부적으로 HPA를 만들어 desiredReplicas(=3)로 올린다. Active=True 가 '창 안' 신호."
end=$((SECONDS + OBSERVE_SECONDS))
while [ "${SECONDS}" -lt "${end}" ]; do
  echo "    [t+$((OBSERVE_SECONDS - (end - SECONDS)))s] $(so_line)"
  sleep 20
done

echo
echo "==> 4) KEDA가 만든 HPA (창 안일 때만 존재할 수 있음) / ScaledObject 상태"
kubectl --context "${CTX}" -n "${NS}" get hpa 2>/dev/null | grep -E 'keda|NAME' || echo "    (지금은 HPA 없음 — 창 밖이라 0 스케일 상태일 수 있음)"
echo
kubectl --context "${CTX}" -n "${NS}" get scaledobject keda-worker-cron 2>/dev/null || true

cat <<'EOF'

정리:
  - KEDA의 핵심 차별점: minReplicaCount:0 → 유휴 시 Pod 0개(비용 0). HPA는 불가능.
  - 동작 모델: 트리거 '비활성' → KEDA가 직접 0으로. 트리거 '활성' → KEDA가 내부
    HPA를 생성해 1..maxReplicaCount 범위를 관리(0↔1 전이는 KEDA, 1↔N은 HPA가 담당).
  - cron은 가장 단순한 트리거다. 실무에선 큐 길이(SQS/Kafka/RabbitMQ), Prometheus
    쿼리 등 '실제 수요 신호'로 스케일한다 — 요청이 오기 '전에' 미리 뜨는 예측성이 장점.
  - ⚖️ 0 스케일의 비용: cold start 지연(0→1 뜨는 시간). 지연 민감 서비스엔 min 1 유지.

정리(리소스 삭제): bash phase-07-scheduling/scripts/99-cleanup.sh
(KEDA 자체 제거까지 원하면 99-cleanup.sh 의 안내 참고)
EOF
