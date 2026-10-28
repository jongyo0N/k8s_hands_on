#!/usr/bin/env bash
# Phase 7 / lab 3 — 무중단 노드 교체 (topology spread + PDB + drain)
# 질문: 노드를 비울 때(drain) PDB는 어떻게 "동시 축출"을 막아 무중단을 지키는가?
# 실행: bash phase-07-scheduling/scripts/03-node-drain-pdb.sh
#
# 주의: -e를 켜지 않는다(관찰 랩). drain이 PDB에 막혀 재시도하는 것 자체가 관찰 포인트.
#       스크립트 끝에서 반드시 uncordon 하여 노드를 원상복구한다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
NS="phase-07"

echo "==> 0) 네임스페이스 준비"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-namespace.yaml" || true

echo
echo "==> 1) Deployment(web, replicas 4) + Service 배포 (topology spread 포함)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/03-web.yaml" || true
kubectl --context "${CTX}" -n "${NS}" rollout status deployment/web --timeout=120s || true

echo
echo "==> 2) PodDisruptionBudget 적용 (maxUnavailable: 1)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/03-pdb.yaml" || true

echo
echo "==> 3) Pod 가 노드에 어떻게 퍼졌나 (topology spread 결과)"
kubectl --context "${CTX}" -n "${NS}" get pods -l app=web -o wide 2>/dev/null || true
echo
echo "    노드별 web Pod 개수:"
kubectl --context "${CTX}" -n "${NS}" get pods -l app=web \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null \
  | sort | uniq -c || true

echo
echo "==> 4) PDB 상태 (ALLOWED DISRUPTIONS = 지금 동시에 쫓아낼 수 있는 최대치)"
kubectl --context "${CTX}" -n "${NS}" get pdb web-pdb 2>/dev/null || true

# web Pod를 가장 많이 안고 있는 워커를 교체 대상으로 고른다.
TARGET="$(kubectl --context "${CTX}" -n "${NS}" get pods -l app=web \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null \
  | sort | uniq -c | sort -rn | head -n1 | awk '{print $2}')"

if [ -z "${TARGET:-}" ]; then
  echo "    교체 대상 노드를 못 찾음. web Pod가 스케줄됐는지 확인 후 재시도."
  exit 0
fi

echo
echo "==> 5) 교체 대상 노드: ${TARGET}"
echo "    이 노드를 drain 한다. --ignore-daemonsets 로 DaemonSet Pod는 제외,"
echo "    --delete-emptydir-data 로 emptyDir 볼륨 Pod도 축출 허용."
echo "    ▶ 관찰 포인트: drain 로그에 'Cannot evict pod ... violate ... disruption budget'"
echo "      (429)이 보이면, PDB가 두 번째 동시 축출을 거부하고 재시도를 유도하는 것."
echo "      즉 '1개 축출 → 대체 Pod Ready 대기 → 다음 1개' 로 직렬화된다 = 무중단."
echo
kubectl --context "${CTX}" drain "${TARGET}" \
  --ignore-daemonsets --delete-emptydir-data --timeout=180s \
  || echo "    (drain 비정상 종료/타임아웃 — 아래 상태로 원인 확인)"

echo
echo "==> 6) drain 후: 대상 노드는 SchedulingDisabled, web Pod는 다른 노드로 재배치"
kubectl --context "${CTX}" get nodes 2>/dev/null || true
echo
kubectl --context "${CTX}" -n "${NS}" get pods -l app=web -o wide 2>/dev/null || true
echo
echo "    (교체 내내 가용 replica 수 — maxUnavailable:1 이라 4개 중 최소 3개 유지)"
kubectl --context "${CTX}" -n "${NS}" get deployment web \
  -o custom-columns='DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas' 2>/dev/null || true

echo
echo "==> 7) 노드 원상복구 (uncordon — 다시 스케줄 가능 상태로)"
kubectl --context "${CTX}" uncordon "${TARGET}" || true

cat <<'EOF'

정리:
  - PDB는 '자발적 중단(drain/업그레이드/delete)'의 동시 발생량만 제한한다.
    비자발적 중단(노드 하드웨어 고장 등)은 PDB로 막지 못한다 — 혼동 주의.
  - drain은 Eviction API를 쓰고, PDB를 위반하는 eviction 요청은 429로 거부된다.
    그래서 동시 축출이 아니라 '예산 안에서 직렬'로 빠진다 → 서비스 가용성 유지.
  - topologySpread(soft)로 애초에 노드/zone에 고루 퍼뜨려 두면, 한 노드가 빠져도
    남은 노드로 충분히 받친다. hard(DoNotSchedule)였다면 drain 중 재배치가
    막혀 교착될 수 있다 → 가용성 목적엔 soft 가 기본값.
  - ⚖️ Karpenter consolidation 같은 공격적 노드 축소는 이 PDB/스프레드와 충돌할 수 있다:
    여러 노드를 한꺼번에 비우려다 PDB에 막혀 consolidation이 지연되거나, 반대로
    PDB가 느슨하면 동시에 너무 많이 빠져 순간 가용성이 흔들린다(완료 기준 질문).

다음: bash phase-07-scheduling/scripts/04-metrics-server-install.sh
정리(리소스 삭제): bash phase-07-scheduling/scripts/99-cleanup.sh
EOF
