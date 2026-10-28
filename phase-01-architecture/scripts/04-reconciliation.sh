#!/usr/bin/env bash
# Phase 1 / lab 4 — reconciliation / 자가치유 (관찰 랩)
# 질문: 나는 "원하는 상태(desired)"만 선언했다. 실제 상태를 거기에 맞추는 건 누구인가?
#       그리고 왜 '이벤트'가 아니라 '현재 vs 목표' 비교로 동작하나(level-triggered)?
# 실행: bash phase-01-architecture/scripts/04-reconciliation.sh
#
# 주의: -e 를 켜지 않는다. Pod 삭제 직후 상태를 훑는 등 타이밍에 의존하는 관찰이 있다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"

echo "==> 0) 전제 확인"
if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
  echo "    클러스터 연결 불가. Phase 0 클러스터를 먼저 띄워라."
  exit 1
fi

echo
echo "==> 1) Deployment(replicas=3) 선언 → 소유 체인 Deployment → ReplicaSet → Pod 가 생긴다"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/web-deployment.yaml"
kubectl --context "${CTX}" rollout status deployment/web --timeout=120s || true
echo
echo "    Deployment / ReplicaSet / Pod 현황:"
kubectl --context "${CTX}" get deploy web 2>/dev/null
kubectl --context "${CTX}" get rs -l app=web 2>/dev/null
kubectl --context "${CTX}" get pods -l app=web -o wide 2>/dev/null
echo
echo "    Pod 하나의 ownerReferences — '누가 나를 만들었나'가 ReplicaSet으로 찍혀 있다:"
kubectl --context "${CTX}" get pods -l app=web \
  -o jsonpath='{range .items[0]}{.metadata.name}{" <- owner: "}{.metadata.ownerReferences[0].kind}{"/"}{.metadata.ownerReferences[0].name}{"\n"}{end}' 2>/dev/null || true

echo
echo "==> 2) 자가치유: Pod 하나를 강제로 지운다 (actual < desired 상황을 만든다)"
VICTIM="$(kubectl --context "${CTX}" get pods -l app=web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
echo "    삭제 대상: ${VICTIM}"
kubectl --context "${CTX}" delete pod "${VICTIM}" --wait=false 2>/dev/null || true
echo "    삭제 직후 즉시 조회 (Terminating 1개 + 새 Pod가 벌써 ContainerCreating 일 수 있다):"
kubectl --context "${CTX}" get pods -l app=web 2>/dev/null
echo "    잠시 뒤 다시 3개로 수렴하는지 확인..."
kubectl --context "${CTX}" wait --for=condition=Ready pod -l app=web --timeout=90s 2>/dev/null || true
kubectl --context "${CTX}" get pods -l app=web 2>/dev/null
cat <<'EOF'
    해석: 아무도 "Pod가 죽었다"는 이벤트를 수동으로 전달하지 않았다. ReplicaSet 컨트롤러는
          주기적으로 '현재 Pod 수 vs 원하는 수(3)'를 비교하다가, 부족하면 새로 만든다.
          → 이벤트 유실에 강하다. 이것이 level-triggered(상태 수렴) 모델이다.
EOF

echo
echo "==> 3) replica 수를 바꾸면 양방향으로 수렴한다 (선언만 바꾸면 add/remove는 컨트롤러가 알아서)"
echo "    3 -> 5 로 늘림 (부족분 2개를 '만든다'):"
kubectl --context "${CTX}" scale deployment/web --replicas=5 2>/dev/null || true
kubectl --context "${CTX}" rollout status deployment/web --timeout=90s || true
kubectl --context "${CTX}" get pods -l app=web --no-headers 2>/dev/null | grep -c . | sed 's/^/    현재 Pod 수: /'
echo
echo "    5 -> 2 로 줄임 (초과분 3개를 '지운다'):"
kubectl --context "${CTX}" scale deployment/web --replicas=2 2>/dev/null || true
sleep 5
kubectl --context "${CTX}" get pods -l app=web -o wide 2>/dev/null
kubectl --context "${CTX}" get pods -l app=web --no-headers 2>/dev/null | grep -c . | sed 's#^#    현재 Pod 수(수렴 중/후): #'
cat <<'EOF'
    해석: 'scale' 은 Deployment spec의 replicas 필드(=desired)를 바꾼 것뿐이다.
          실제로 Pod를 만들고 지우는 건 컨트롤러이고, 목표 숫자 하나만 보고 양방향으로 수렴시킨다.
          → "어떻게(명령형)"가 아니라 "무엇을 원하는지(선언형)"만 기술하는 모델.
EOF

echo
echo "==> 4) 정리 (Deployment 삭제 — 소유 체인을 따라 RS/Pod도 함께 사라진다)"
kubectl --context "${CTX}" delete -f "${MANIFESTS}/web-deployment.yaml" --ignore-not-found >/dev/null 2>&1 \
  && echo "    web Deployment 삭제 (ReplicaSet/Pod는 cascade로 정리됨)" || true

echo
echo "Phase 1 랩 끝. 관찰 결과와 완료 기준 답을 phase-01-architecture/NOTES.md 에 적는다."
