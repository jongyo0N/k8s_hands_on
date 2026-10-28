#!/usr/bin/env bash
# Phase 3 / lab 4 — externalTrafficPolicy: Local vs Cluster (관찰/비교)
# 질문: NodePort로 들어온 트래픽의 '출발지 IP'는 보존되는가? 노드 간 분배는 균등한가?
# 실행: bash phase-03-services/scripts/04-external-traffic-policy.sh
#
# 관찰 랩이라 -e 미사용. Local 정책에서 '엔드포인트 없는 노드'를 때리면 curl이 실패(drop)하는데,
# 그 실패 자체가 관찰 대상이므로 || 로 흘려보낸다. (set -uo + || true)
#
# ── kind 환경 한계(꼭 읽을 것) ────────────────────────────────────────────────
#  * kind 노드 = Docker 컨테이너. macOS에선 노드 컨테이너 IP가 호스트에서 직접 라우팅되지
#    않아 호스트 curl로 NodePort를 때리기 어렵다(Phase 0 kind-config엔 extraPortMappings도 없음).
#    그래서 hostNetwork 클라이언트 Pod(netshoot)를 worker 한 대에 고정해 '노드 안'에서 호출한다.
#  * 따라서 여기서 관찰되는 '클라이언트 IP'는 진짜 외부 IP가 아니라 '클라이언트가 올라간 노드 IP'다.
#    그래도 Local(소스 IP 보존) vs Cluster(SNAT로 치환)의 '차이'는 그대로 드러난다.
#  * Local 정책의 진짜 가치(진짜 외부 클라이언트 IP 보존, hop 제거)는 실제 L4 LB/베어메탈에서 빛난다.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

CTX="kind-k8s-mastery"
NS="phase-03"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CLIENT_NODE="k8s-mastery-worker"   # hostNetwork 클라이언트가 고정된 노드(=호출 출발지)
WORKERS=("k8s-mastery-worker" "k8s-mastery-worker2" "k8s-mastery-worker3")

echo "==> 0) 백엔드(agnhost netexec x2) + NodePort 서비스 2개(Cluster/Local) + hostNetwork 클라이언트 배포"
echo "    백엔드는 podAntiAffinity로 서로 다른 worker에 떨어진다 -> worker 3대 중 1대는 '엔드포인트 없음'."
kubectl --context "$CTX" apply -f "${MANIFESTS}/00-namespace.yaml"
kubectl --context "$CTX" apply -f "${MANIFESTS}/04-external-traffic-policy.yaml"
kubectl --context "$CTX" -n "$NS" rollout status deployment/etp-backend --timeout=120s
kubectl --context "$CTX" -n "$NS" wait --for=condition=Ready pod/etp-client --timeout=120s

echo
echo "==> 1) 백엔드 Pod가 어느 노드에 있나 (어느 worker에 엔드포인트가 있고 없는지 확인)"
kubectl --context "$CTX" -n "$NS" get pods -l app=etp-backend -o wide

echo
echo "==> 2) 두 서비스의 NodePort 번호 + 정책"
NP_CLUSTER="$(kubectl --context "$CTX" -n "$NS" get svc etp-cluster -o jsonpath='{.spec.ports[0].nodePort}')"
NP_LOCAL="$(kubectl --context "$CTX" -n "$NS" get svc etp-local -o jsonpath='{.spec.ports[0].nodePort}')"
kubectl --context "$CTX" -n "$NS" get svc etp-cluster etp-local \
  -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,ETP:.spec.externalTrafficPolicy,NODEPORT:.spec.ports[0].nodePort,HC_NODEPORT:.spec.healthCheckNodePort'
echo "    etp-cluster NodePort=${NP_CLUSTER:-?} (externalTrafficPolicy=Cluster)"
echo "    etp-local   NodePort=${NP_LOCAL:-?} (externalTrafficPolicy=Local, healthCheckNodePort 자동 할당됨)"

# 노드 이름 -> InternalIP
nodeip() {
  kubectl --context "$CTX" get node "$1" \
    -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null
}
# 클라이언트(hostNetwork, worker1) netns 에서 대상 노드의 NodePort 를 때린다.
hit() { # $1=nodeIP  $2=nodePort  $3=path
  kubectl --context "$CTX" -n "$NS" exec "etp-client" -- \
    curl -s --max-time 3 "http://$1:$2/$3" 2>/dev/null
}

echo
echo "==> 3) [Cluster 정책] 각 worker의 NodePort를 ${CLIENT_NODE} 에서 여러 번 호출"
echo "    기대: 모든 노드가 응답(필요시 다른 노드로 hop). 단, /clientip 는 SNAT 되어 '노드 IP'로 보임."
for w in "${WORKERS[@]}"; do
  ip="$(nodeip "$w")"; [[ -z "$ip" ]] && { echo "    [$w] InternalIP 못 구함, skip"; continue; }
  echo "    --- target ${w} (${ip}:${NP_CLUSTER}) ---"
  for n in 1 2 3; do
    host="$(hit "$ip" "$NP_CLUSTER" hostname || true)"
    cip="$(hit "$ip" "$NP_CLUSTER" clientip || true)"
    echo "      try${n}: served-by-pod=${host:-<no-response>}  seen-client-ip=${cip:-<no-response>}"
  done
done

echo
echo "==> 4) [Local 정책] 같은 방식으로 호출"
echo "    기대: '로컬 엔드포인트가 있는' 노드만 응답(없는 노드는 drop=불균형),"
echo "         대신 /clientip 는 SNAT 없이 '호출자(${CLIENT_NODE}) IP'로 보존된다."
for w in "${WORKERS[@]}"; do
  ip="$(nodeip "$w")"; [[ -z "$ip" ]] && { echo "    [$w] InternalIP 못 구함, skip"; continue; }
  echo "    --- target ${w} (${ip}:${NP_LOCAL}) ---"
  for n in 1 2 3; do
    host="$(hit "$ip" "$NP_LOCAL" hostname || true)"
    cip="$(hit "$ip" "$NP_LOCAL" clientip || true)"
    if [[ -z "$host" ]]; then
      echo "      try${n}: (응답 없음 — 이 노드엔 로컬 엔드포인트가 없어 Local 정책상 drop)"
    else
      echo "      try${n}: served-by-pod=${host}  seen-client-ip=${cip:-?}"
    fi
  done
done

cat <<EOF

    해석:
      - Cluster(기본): 어떤 노드로 들어와도 클러스터 전체 엔드포인트로 분배한다. 받은 노드에
        로컬 Pod가 없으면 '다른 노드로 한 번 더 hop' + 그 과정의 SNAT로 Pod가 보는 출발지 IP가
        '마지막에 거친 노드 IP'로 바뀐다(원본 클라이언트 IP 소실). 대신 노드별 분배가 균등.
      - Local: 받은 노드의 '로컬 엔드포인트'로만 보낸다. hop/SNAT 없음 -> 출발지 IP 보존.
        대신 로컬 엔드포인트 없는 노드는 트래픽을 버린다 -> 노드별 Pod 수가 다르면 부하 불균형.
        그래서 보통 (a) 엔드포인트를 노드에 고루 펴거나 (b) 외부 LB가 healthCheckNodePort로
        '엔드포인트 있는 노드만' 백엔드에 넣는다.
      - 트레이드오프: Local = 소스 IP 보존 + hop 제거(지연↓) vs 불균형/노드 선정 복잡.
                      Cluster = 균등·단순 vs 소스 IP 소실 + 가끔 추가 hop.

    kind 한계 재확인: 위 '클라이언트 IP'는 hostNetwork 클라이언트가 올라간 노드(${CLIENT_NODE})의 IP다.
      Local에서 그 IP가 '보존'되고 Cluster에서 '다른 노드 IP로 치환'되는 대비를 보면 핵심은 확인된다.

다음: 다 끝났으면  bash phase-03-services/scripts/99-cleanup.sh
EOF
