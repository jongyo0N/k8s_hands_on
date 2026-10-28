#!/usr/bin/env bash
# Phase 5 / lab 4 — CloudNativePG: PostgreSQL 클러스터 + 페일오버 관찰
# 질문: primary Pod를 지우면 operator가 어떻게 새 primary를 승격하나?
# 실행: bash phase-05-storage/scripts/04-cnpg-failover.sh
#
# install/배포는 결정적이라 -e를 켜고, 관찰(폴링)은 항상 0을 반환하도록 감싼다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CTX="kind-k8s-mastery"
NS="phase-05"

# --- 버전 핀 (최신 확인: https://github.com/cloudnative-pg/cloudnative-pg/releases) ---
CNPG_VERSION="1.30.1"
CNPG_BRANCH="release-1.30"
CNPG_MANIFEST="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/${CNPG_BRANCH}/releases/cnpg-${CNPG_VERSION}.yaml"
CNPG_NS="cnpg-system"

kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f - >/dev/null 2>&1 || true

echo "==> 1) CloudNativePG operator 설치 (v${CNPG_VERSION}, server-side apply)"
echo "    manifest: ${CNPG_MANIFEST}"
echo "    (helm 선호 시: helm repo add cnpg https://cloudnative-pg.github.io/charts &&"
echo "     helm upgrade --install cnpg cnpg/cloudnative-pg -n ${CNPG_NS} --create-namespace --version <차트버전>)"
kubectl --context "${CTX}" apply --server-side -f "${CNPG_MANIFEST}"

echo
echo "==> 2) CRD 등록 + operator Deployment Available 대기"
kubectl --context "${CTX}" wait --for=condition=established --timeout=120s \
  crd/clusters.postgresql.cnpg.io || true
kubectl --context "${CTX}" -n "${CNPG_NS}" wait --for=condition=Available --timeout=240s \
  deployment -l app.kubernetes.io/name=cloudnative-pg || true
kubectl --context "${CTX}" -n "${CNPG_NS}" get deploy,pod

echo
echo "==> 3) PostgreSQL Cluster(CR) 배포 — instances=3 (primary 1 + standby 2)"
# CRD 등록 레이스 대비 재시도 (if 조건이라 -e로 중단되지 않음)
for i in $(seq 1 12); do
  if kubectl --context "${CTX}" apply -f "${MANIFESTS}/04-pg-cluster.yaml"; then
    break
  fi
  echo "    CRD 등록 대기 중... 재시도 (${i})"
  sleep 5
done

echo
echo "==> 4) 클러스터가 건강해질 때까지 대기 (PVC WFFC + 이미지 pull로 수 분 소요 가능)"
for _ in $(seq 1 60); do
  ready="$(kubectl --context "${CTX}" -n "${NS}" get cluster pg-sample \
            -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)"
  phase="$(kubectl --context "${CTX}" -n "${NS}" get cluster pg-sample \
            -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  echo "    readyInstances=${ready:-0}/3  phase=${phase:-?}"
  if [ "${ready:-0}" = "3" ]; then
    break
  fi
  sleep 10
done

echo
echo "==> 5) 클러스터 현황 + 각 Pod의 역할(primary/replica)"
kubectl --context "${CTX}" -n "${NS}" get cluster pg-sample \
  -o custom-columns='CLUSTER:.metadata.name,INSTANCES:.spec.instances,READY:.status.readyInstances,PRIMARY:.status.currentPrimary' \
  2>/dev/null || true
# 역할 라벨은 버전에 따라 role / cnpg.io/instanceRole 둘 다 있을 수 있어 모두 출력
kubectl --context "${CTX}" -n "${NS}" get pods -l cnpg.io/cluster=pg-sample -o wide \
  -L role -L cnpg.io/instanceRole 2>/dev/null || true

OLD_PRIMARY="$(kubectl --context "${CTX}" -n "${NS}" get cluster pg-sample \
  -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
echo
echo "    현재 primary: ${OLD_PRIMARY:-<미상>}"
if [ -z "${OLD_PRIMARY}" ]; then
  echo "    [중단] primary를 아직 못 찾음. 'kubectl -n ${NS} describe cluster pg-sample'로 상태 확인."
  exit 0
fi

echo
echo "==> 6) [페일오버 유발] primary Pod 삭제: ${OLD_PRIMARY}"
kubectl --context "${CTX}" -n "${NS}" delete pod "${OLD_PRIMARY}" --wait=false || true

echo
echo "==> 7) [관찰] operator가 standby 하나를 새 primary로 승격하는 과정"
NEW_PRIMARY="${OLD_PRIMARY}"
for _ in $(seq 1 36); do
  cur="$(kubectl --context "${CTX}" -n "${NS}" get cluster pg-sample \
          -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
  tgt="$(kubectl --context "${CTX}" -n "${NS}" get cluster pg-sample \
          -o jsonpath='{.status.targetPrimary}' 2>/dev/null || true)"
  echo "    currentPrimary=${cur:-?}  targetPrimary=${tgt:-?}"
  if [ -n "${cur}" ] && [ "${cur}" != "${OLD_PRIMARY}" ]; then
    NEW_PRIMARY="${cur}"
    break
  fi
  sleep 5
done

echo
echo "    페일오버 관련 events (최근):"
kubectl --context "${CTX}" -n "${NS}" get events --sort-by=.lastTimestamp 2>/dev/null \
  | grep -Ei 'pg-sample|primary|promot|failover|switchover' | tail -n 15 || true

echo
echo "==> 8) 결과: 새 primary + 삭제됐던 인스턴스의 재합류(standby)"
echo "    old primary: ${OLD_PRIMARY}"
echo "    new primary: ${NEW_PRIMARY}"
kubectl --context "${CTX}" -n "${NS}" get pods -l cnpg.io/cluster=pg-sample -o wide \
  -L role -L cnpg.io/instanceRole 2>/dev/null || true
kubectl --context "${CTX}" -n "${NS}" get cluster pg-sample \
  -o custom-columns='CLUSTER:.metadata.name,READY:.status.readyInstances,PRIMARY:.status.currentPrimary' \
  2>/dev/null || true

cat <<'EOF'

    정리:
      - primary Pod가 사라지자 operator가 standby를 승격(failover)하고,
        -rw Service 엔드포인트가 새 primary를 가리키도록 갱신한다.
      - 삭제된 인스턴스는 그 PVC/데이터로 다시 떠서 standby로 재합류한다.
      - "DB on k8s"의 핵심 가치가 이 자동화. (NOTES.md에 찬반 논거 3개씩 정리하라.)

    접속해 데이터 정합성을 보고 싶으면(선택):
      kubectl --context kind-k8s-mastery -n phase-05 exec -it pg-sample-1 -- \
        psql -U postgres -c 'SELECT pg_is_in_recovery();'   # primary=f, standby=t
EOF

echo
echo "정리하려면: bash phase-05-storage/scripts/99-cleanup.sh"
