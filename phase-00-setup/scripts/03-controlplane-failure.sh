#!/usr/bin/env bash
# Phase 0 / lab 3 — control-plane가 내려가면? (관찰 랩)
# 질문: control-plane이 죽어도 기존 Pod는 왜 계속 도는가?
# 실행: bash phase-00-setup/scripts/03-controlplane-failure.sh
#
# 주의: -e를 켜지 않는다. 중간에 "일부러 실패하는" 명령(API 다운 중 kubectl)이 있기 때문.
set -uo pipefail

CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
CP="${CLUSTER_NAME}-control-plane"

echo "==> 1) 샘플 워크로드 배포 (nginx, replica 2)"
kubectl --context "${CTX}" create deployment web --image=nginx:1.27-alpine --replicas=2 2>/dev/null \
  || echo "    (이미 존재 — 재사용)"
kubectl --context "${CTX}" rollout status deployment/web --timeout=120s

echo
echo "==> 2) 노드 컨테이너 현황 (kind는 각 노드를 Docker 컨테이너로 돌린다)"
docker ps --filter "name=${CLUSTER_NAME}-" --format 'table {{.Names}}\t{{.Status}}'

echo
echo "==> 3) control-plane 컨테이너 정지: ${CP}"
docker stop "${CP}" >/dev/null
echo "    정지 완료."

echo
echo "==> 4) 지금 API server와 대화 시도 (실패가 정상):"
kubectl --context "${CTX}" get nodes --request-timeout=5s \
  || echo "    <-- 예상대로 API server 응답 없음. '관제탑'이 꺼진 상태."

echo
echo "==> 5) 그런데 앱 컨테이너는 살아있는가? 워커의 containerd에 직접 물어본다 (crictl):"
for w in $(docker ps --filter "name=${CLUSTER_NAME}-worker" --format '{{.Names}}'); do
  echo "    [${w}]"
  docker exec "${w}" crictl ps 2>/dev/null | grep -E 'CONTAINER|nginx' || echo "      (이 워커엔 web pod 없음)"
done
cat <<'EOF'
    해석: 워크로드는 그대로 돈다. 노드의 kubelet + containerd는 "이미 받은 spec"대로
          컨테이너를 유지할 뿐, control-plane이 매 순간 살아있어야 할 필요가 없다.
          control-plane은 "상태를 바꾸는" 주체다 — 스케줄링, 스케일, 자가치유, 응답(kubectl).
          그래서 control-plane 다운 = "변경·관측 불가"이지, "서비스 중단"이 아니다.
          (단, 이 시간 동안 Pod가 죽으면 재생성은 안 된다. 자가치유도 control-plane 일이니까.)
EOF

echo
echo "==> 6) control-plane 재기동"
docker start "${CP}" >/dev/null
printf "    API 복구 대기"
for _ in $(seq 1 30); do
  if kubectl --context "${CTX}" get --raw='/readyz' >/dev/null 2>&1; then
    printf " ... 복구됨!\n"; break
  fi
  printf "."; sleep 2
done

echo
echo "==> 7) 최종 상태"
kubectl --context "${CTX}" get nodes
kubectl --context "${CTX}" get pods -o wide -l app=web

echo
echo "정리하려면: bash phase-00-setup/scripts/99-cleanup.sh"
