#!/usr/bin/env bash
# Phase 2 / lab 3 — StatefulSet identity: Pod 강제 삭제 후 같은 이름/PVC로 재생성 관찰
# 실행: bash phase-02-workloads/scripts/03-statefulset.sh
#
# 주의: -e를 켜지 않는다. 강제 삭제 → 재생성 대기 등 레이스가 있는 관찰 랩이다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="phase-02"
M="${SCRIPT_DIR}/../manifests/03-statefulset"

echo "==> 0) 네임스페이스 보장"
kubectl --context "${CTX}" apply -f "${SCRIPT_DIR}/../manifests/00-namespace.yaml" >/dev/null

echo
echo "==> 1) headless Service + redis StatefulSet(replicas=3) 배포"
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/headless-service.yaml"
kubectl --context "${CTX}" -n "${NS}" apply -f "${M}/redis-statefulset.yaml"

echo
echo "==> 2) 3개 Pod가 순서대로(redis-0 → 1 → 2) Ready 될 때까지 대기"
kubectl --context "${CTX}" -n "${NS}" rollout status statefulset/redis --timeout=180s || true

echo
echo "==> 3) 현재 Pod와 PVC (각 ordinal에 전용 PVC가 1:1 바인딩됨)"
kubectl --context "${CTX}" -n "${NS}" get pods -l app=redis -o wide 2>/dev/null || true
kubectl --context "${CTX}" -n "${NS}" get pvc 2>/dev/null || true

echo
echo "==> 4) redis-0에 데이터 기록"
kubectl --context "${CTX}" -n "${NS}" exec redis-0 -- redis-cli set canary "written-before-delete" >/dev/null 2>&1 || true
echo "    기록값 canary = $(kubectl --context "${CTX}" -n "${NS}" exec redis-0 -- redis-cli get canary 2>/dev/null)"

echo
echo "==> 5) 삭제 전 redis-0의 UID / PVC 기록 (재생성 후 비교용)"
OLD_UID="$(kubectl --context "${CTX}" -n "${NS}" get pod redis-0 -o jsonpath='{.metadata.uid}' 2>/dev/null)"
OLD_PVC="$(kubectl --context "${CTX}" -n "${NS}" get pod redis-0 -o jsonpath='{.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}' 2>/dev/null)"
echo "    redis-0 UID(삭제 전) = ${OLD_UID}"
echo "    redis-0 가 쓰는 PVC  = ${OLD_PVC}   (ordinal 0에 고정)"

echo
echo "==> 6) redis-0 강제 삭제 (grace 0 + --force) — '노드 증발/Pod 소실'을 흉내"
kubectl --context "${CTX}" -n "${NS}" delete pod redis-0 --grace-period=0 --force 2>/dev/null || true

echo
echo "==> 7) 같은 이름(redis-0)으로 재생성될 때까지 대기 → UID/PVC 비교"
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Ready pod/redis-0 --timeout=120s 2>/dev/null || true
NEW_UID="$(kubectl --context "${CTX}" -n "${NS}" get pod redis-0 -o jsonpath='{.metadata.uid}' 2>/dev/null)"
NEW_PVC="$(kubectl --context "${CTX}" -n "${NS}" get pod redis-0 -o jsonpath='{.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}' 2>/dev/null)"
echo "    redis-0 UID(삭제 후) = ${NEW_UID}   (<- 새 Pod이므로 UID는 달라진다)"
echo "    redis-0 가 쓰는 PVC  = ${NEW_PVC}   (<- OLD와 같으면 identity 유지!)"

echo
echo "==> 8) 데이터 생존 확인 (같은 PVC에 재부착됐다면 canary가 그대로여야 한다)"
echo "    canary(삭제 후) = $(kubectl --context "${CTX}" -n "${NS}" exec redis-0 -- redis-cli get canary 2>/dev/null)"

echo
cat <<'EOF'
==> 해석
    - Pod UID는 바뀐다(= 물리적으로 새 Pod). 그러나 이름 redis-0, DNS
      redis-0.redis-headless.phase-02.svc.cluster.local, PVC data-redis-0은 그대로다.
      이 "안정적 identity(이름·네트워크·스토리지)"가 StatefulSet의 핵심 보장.
    - canary가 살아남은 이유: 재생성된 redis-0가 같은 PVC(data-redis-0)에 재부착됐고,
      redis AOF(appendfsync always)가 디스크에 기록해 뒀기 때문. StatefulSet이 데이터를
      복제해 준 게 아니다.
    - 보장하지 '않는' 것: redis-0/1/2는 서로 독립 인스턴스다. 노드 간 데이터 복제, 리더 선출,
      failover는 StatefulSet의 몫이 아니다 (redis replication/sentinel 또는 operator 필요).
      → 완료 기준 Q3.
EOF

echo
echo "정리: kubectl --context ${CTX} -n ${NS} delete -f ${M}"
echo "      PVC는 StatefulSet 삭제로 자동 삭제되지 않는다(의도된 데이터 보호). 수동 삭제:"
echo "      kubectl --context ${CTX} -n ${NS} delete pvc -l app=redis"
echo "다음: bash phase-02-workloads/scripts/04-job-podfailurepolicy.sh"
