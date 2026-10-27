#!/usr/bin/env bash
# Phase 1 / lab 3 — scheduler를 멈추면? (관찰 랩)
# 질문: Pod를 "노드에 올리는" 일의 경계는 어디인가? scheduler가 꼭 해야 하는 일은?
# 실행: bash phase-01-architecture/scripts/03-stop-scheduler.sh
#
# 주의: -e 를 켜지 않는다. "일부러 Pending에 머무는" 관찰 단계가 있고,
#       EXIT trap으로 scheduler를 반드시 원복해 클러스터를 성한 상태로 되돌린다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
CP="${CLUSTER_NAME}-control-plane"
SCHED_MANIFEST="/etc/kubernetes/manifests/kube-scheduler.yaml"
SCHED_BACKUP="/tmp/kube-scheduler.yaml"

restore_scheduler() {
  # /tmp 에 치워둔 매니페스트가 있으면 제자리로 돌려 scheduler를 복구한다.
  docker exec "${CP}" sh -c "test -f ${SCHED_BACKUP} && mv ${SCHED_BACKUP} ${SCHED_MANIFEST}" 2>/dev/null || true
}
trap restore_scheduler EXIT  # 중간에 Ctrl-C로 끊겨도 scheduler는 되돌려 놓는다.

sched_running() {  # kube-scheduler 정적 Pod가 Running 이면 0
  kubectl --context "${CTX}" -n kube-system get pods -l component=kube-scheduler \
    -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running
}
sched_gone() {     # kube-scheduler mirror Pod가 사라졌으면 0
  ! kubectl --context "${CTX}" -n kube-system get pods -l component=kube-scheduler \
    -o name 2>/dev/null | grep -q .
}

echo "==> 0) 전제 확인"
if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
  echo "    클러스터 연결 불가. Phase 0 클러스터를 먼저 띄워라."
  exit 1
fi

echo
echo "==> 1) 지금 scheduler는 control-plane의 static pod로 돌고 있다"
kubectl --context "${CTX}" -n kube-system get pods -l component=kube-scheduler -o wide || true

echo
echo "==> 2) scheduler 매니페스트를 /tmp 로 치워 static pod를 내린다"
echo "    (kubelet이 /etc/kubernetes/manifests 를 감시하다 파일이 사라지면 그 Pod를 죽인다)"
docker exec "${CP}" mv "${SCHED_MANIFEST}" "${SCHED_BACKUP}" \
  && echo "    mv 완료 — scheduler 종료 대기..." || echo "    (mv 실패 — control-plane 컨테이너/경로 확인)"
for _ in $(seq 1 30); do sched_gone && break; printf '.'; sleep 2; done; echo
kubectl --context "${CTX}" -n kube-system get pods -l component=kube-scheduler 2>/dev/null \
  | grep -q . && echo "    (아직 보이면 몇 초 더 기다렸다 재확인)" || echo "    scheduler 사라짐 확인."

echo
echo "==> 3) scheduler가 없는 상태에서 Pod 2개를 만든다"
echo "    (a) nodeName 없는 평범한 Pod  → 누가 노드를 골라줘야 뜬다"
echo "    (b) nodeName을 직접 박은 Pod  → binding이 이미 끝난 셈"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/pending-pod.yaml" || true
kubectl --context "${CTX}" apply -f "${MANIFESTS}/pinned-pod.yaml" || true

echo
echo "    pinned Pod가 Ready 될 때까지 잠깐 대기 (이미지 pull 포함)..."
kubectl --context "${CTX}" wait --for=condition=Ready pod/sched-pinned --timeout=90s 2>/dev/null || true
sleep 3

echo
echo "==> 4) 결과 관찰 — 한쪽은 Running, 한쪽은 Pending"
kubectl --context "${CTX}" get pod sched-pending sched-pinned -o wide 2>/dev/null || true
echo
echo "    sched-pending 을 describe 해보면 '아무도 스케줄링하지 않고 있음'이 보인다:"
kubectl --context "${CTX}" describe pod sched-pending 2>/dev/null \
  | grep -E 'Status:|Node:|Conditions:|PodScheduled|Events:|<none>|Warning|FailedScheduling' | head -n 10 || true
cat <<'EOF'
    해석:
      - sched-pinned 은 Running. nodeName이 이미 채워져 있어 "그 노드의 kubelet"이 바로 집어갔다.
        → 컨테이너를 실제로 띄우는 건 kubelet+CRI(containerd)이지 scheduler가 아니다.
      - sched-pending 은 Pending. nodeName이 비어 있는데 그걸 채워줄 scheduler가 없다.
        → scheduler의 본질적 역할은 딱 하나: "적합한 노드를 골라 nodeName(=Binding)을 채우는 것".
EOF

echo
echo "==> 5) scheduler 매니페스트 원복 → 복구되면 Pending Pod가 저절로 스케줄된다"
restore_scheduler
printf "    scheduler 복구 대기"
for _ in $(seq 1 30); do sched_running && { printf " ... 복구됨!\n"; break; }; printf '.'; sleep 2; done
echo "    (방금 전까지 Pending이던) sched-pending 이 노드를 배정받는지 확인:"
kubectl --context "${CTX}" wait --for=condition=Ready pod/sched-pending --timeout=90s 2>/dev/null || true
kubectl --context "${CTX}" get pod sched-pending sched-pinned -o wide 2>/dev/null || true
echo "    → 같은 선언(Pending Pod)이 환경이 정상화되자 '수렴'했다. (level-triggered 체감)"

echo
echo "==> 6) 정리 (관찰용 Pod 삭제 — scheduler는 이미 원복됨)"
kubectl --context "${CTX}" delete pod sched-pending sched-pinned --ignore-not-found >/dev/null 2>&1 \
  && echo "    sched-pending / sched-pinned 삭제" || true

echo
echo "다음: bash phase-01-architecture/scripts/04-reconciliation.sh"
