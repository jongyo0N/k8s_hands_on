#!/usr/bin/env bash
# Phase 5 / lab 3 — RWO 볼륨과 노드 장애 (관찰 랩)
# 질문: RWO PVC를 쓰는 Pod의 노드를 내리면, Pod는 다른 노드에서 바로 뜨는가?
# 실행: bash phase-05-storage/scripts/03-rwo-multiattach.sh
#
# 주의: -e 안 켬. 일부러 노드를 drain 해서 "스케줄 실패"를 관찰한다.
#       끝에서 uncordon으로 되돌린다(중간에 끊겨도 99-cleanup이 다시 uncordon 시도).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CTX="kind-k8s-mastery"
NS="phase-05"

kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f - >/dev/null 2>&1 || true

echo "==> 1) RWO PVC + Deployment 배포 (app-tier 워커에 고정, strategy=Recreate)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/03-rwo-pvc.yaml"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/03-rwo-deployment.yaml"
kubectl --context "${CTX}" -n "${NS}" rollout status deployment/rwo-app --timeout=120s || true

echo
echo "==> 2) Pod가 어느 노드에 떴는지 + 볼륨이 그 노드에 묶였는지 확인"
kubectl --context "${CTX}" -n "${NS}" get pods -l app=rwo-app -o wide
NODE="$(kubectl --context "${CTX}" -n "${NS}" get pod -l app=rwo-app \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)"
echo "    rwo-app Pod가 뜬 노드: ${NODE:-<없음>}"
if [ -z "${NODE}" ]; then
  echo "    [중단] 실행 중인 Pod를 못 찾음. 노드 수/리소스를 확인하라."
  exit 0
fi
PV_RWO="$(kubectl --context "${CTX}" -n "${NS}" get pvc rwo-data -o jsonpath='{.spec.volumeName}' 2>/dev/null)"
echo "    PV ${PV_RWO:-?} 의 nodeAffinity:"
kubectl --context "${CTX}" get pv "${PV_RWO}" \
  -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}' 2>/dev/null || true

echo
echo "==> 3) 데이터가 쌓이는지 확인 (heartbeat.log)"
sleep 6
kubectl --context "${CTX}" -n "${NS}" exec deploy/rwo-app -- sh -c 'tail -n 3 /data/heartbeat.log' 2>/dev/null \
  || echo "    (아직 로그 없음 — 무시)"

echo
echo "==> 4) [장애 유발] Pod가 떠 있는 노드 '${NODE}' 를 drain"
echo "    drain = cordon(신규 스케줄 금지) + 기존 Pod eviction."
echo "    (더 가혹한 버전: docker stop ${NODE}  → 노드 NotReady, ~5분 후 eviction. 여기선 drain 사용.)"
kubectl --context "${CTX}" drain "${NODE}" \
  --ignore-daemonsets --delete-emptydir-data --force --timeout=90s || true

echo
echo "==> 5) [관찰] 새 Pod는 다른 app-tier 워커로 가려 하지만 볼륨이 못 따라온다"
sleep 10
kubectl --context "${CTX}" -n "${NS}" get pods -l app=rwo-app -o wide
echo
echo "    새 Pod의 events:"
NEWPOD="$(kubectl --context "${CTX}" -n "${NS}" get pod -l app=rwo-app \
  --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -n "${NEWPOD}" ]; then
  kubectl --context "${CTX}" -n "${NS}" describe pod "${NEWPOD}" | sed -n '/Events:/,$p'
fi
cat <<EOF
    기대 증상(local-path):
      FailedScheduling: "node(s) had volume node affinity conflict" + "node(s) were unschedulable"
      = 데이터가 drain된 노드(${NODE})에 묶여 있어, 다른 노드로 Pod가 못 간다.

    클라우드 CSI(EBS 등)에서는 같은 교훈이 이렇게 보인다:
      - "Multi-Attach error for volume ... Volume is already used by pod(s) ..."
      - 옛 노드에서 detach가 끝나야 새 노드에 attach → attach/detach controller의
        강제 detach 타임아웃(기본 ~6분) 때문에 Pod 복구가 지연된다.
    공통 교훈: RWO는 "노드" 단위 단일 attach. 데이터는 Pod를 자동으로 따라오지 않는다.
EOF

echo
echo "==> 6) [복구] 노드 uncordon → Pod가 '데이터가 있는 그 노드'로 돌아가 뜬다"
kubectl --context "${CTX}" uncordon "${NODE}" || true
kubectl --context "${CTX}" -n "${NS}" rollout status deployment/rwo-app --timeout=120s || true
kubectl --context "${CTX}" -n "${NS}" get pods -l app=rwo-app -o wide

echo
echo "==> 7) 데이터 보존 확인 — 같은 볼륨이라 heartbeat.log가 이어진다"
kubectl --context "${CTX}" -n "${NS}" exec deploy/rwo-app -- sh -c 'wc -l /data/heartbeat.log; tail -n 3 /data/heartbeat.log' 2>/dev/null \
  || echo "    (Pod가 아직 Ready 전이면 잠시 후 다시 시도)"

cat <<'EOF'

    정리: StatefulSet이었다면 같은 Pod 이름/PVC로 "그 노드에서만" 재생성되며 동일 교착을 겪는다.
          노드 장애 = local 데이터 접근 불가. 그래서 상태ful엔 네트워크/분산 스토리지나
          operator 수준의 복제(lab 4)가 필요하다. (NOTES.md에 drain~복구 타임라인을 적어라.)
EOF

echo
echo "다음: bash phase-05-storage/scripts/04-cnpg-failover.sh"
