#!/usr/bin/env bash
# Phase 3 / lab 1 — ClusterIP는 "iptables 규칙"일 뿐: NAT 체인을 손으로 추적
# 질문: ClusterIP(가상 IP)로 보낸 패킷은 누가/어디서 실제 Pod IP로 바꿔치기하는가?
# 실행: bash phase-03-services/scripts/01-clusterip-iptables.sh
#
# 관찰/추적 랩이라 -e를 켜지 않는다. `iptables-save | grep ...` 파이프가 매치 없음(exit 1)을
# 낼 수 있고, 그래도 다음 단계로 계속 진행해야 하기 때문. (CONVENTIONS: 관찰은 set -uo + || true)
set -uo pipefail

CTX="kind-k8s-mastery"
NS="phase-03"
NODE="k8s-mastery-worker"          # NAT 체인을 들여다볼 노드 컨테이너 (kube-proxy가 여기 규칙을 심음)
SVC="clusterip-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"

echo "==> 0) 네임스페이스 + 워크로드 배포 (nginx x3 + ClusterIP Service)"
kubectl --context "$CTX" apply -f "${MANIFESTS}/00-namespace.yaml"
kubectl --context "$CTX" apply -f "${MANIFESTS}/01-clusterip.yaml"
kubectl --context "$CTX" -n "$NS" rollout status deployment/web --timeout=120s

echo
echo "==> 1) Service와 그 뒤의 Pod/EndpointSlice 확인"
kubectl --context "$CTX" -n "$NS" get svc "$SVC" -o wide
CLUSTERIP="$(kubectl --context "$CTX" -n "$NS" get svc "$SVC" -o jsonpath='{.spec.clusterIP}')"
echo "    clusterIP = ${CLUSTERIP}   <- 이 IP를 가진 네트워크 인터페이스는 '어디에도 없다'(아래 2단계)"
echo
echo "    실제 트래픽을 받을 Pod들 (EndpointSlice):"
kubectl --context "$CTX" -n "$NS" get endpointslices -l "kubernetes.io/service-name=${SVC}" \
  -o custom-columns='SLICE:.metadata.name,ADDRS:.endpoints[*].addresses,READY:.endpoints[*].conditions.ready,PORTS:.ports[*].port'
echo "    (참고) Pod IP 목록:"
kubectl --context "$CTX" -n "$NS" get pods -l app=web -o wide

# 노드의 nat 테이블을 한 번만 덤프해 캐싱(여러 번 grep). kube-proxy 규칙은 노드의 root netns에 있다.
echo
echo "==> (노드 ${NODE} 의 nat 테이블 덤프: docker exec ${NODE} iptables-save -t nat)"
NAT="$(docker exec "$NODE" iptables-save -t nat 2>/dev/null)"
if [[ -z "$NAT" ]]; then
  echo "    (!) nat 테이블을 못 읽음 — 노드 컨테이너 이름('${NODE}')과 docker 실행 상태 확인."
fi

echo
echo "==> 2) clusterIP를 가진 네트워크 장치가 정말 '없는지' 확인"
echo "    ip addr 목록에 ${CLUSTERIP} 가 나오면 안 된다:"
if docker exec "$NODE" ip -o addr 2>/dev/null | grep -q "${CLUSTERIP}"; then
  echo "    (!) 장치에 붙어있다? (예상 밖)"
else
  echo "    -> 없음. clusterIP는 인터페이스에 바인딩된 적이 없는 '순수 가상' IP. '접속 대상'이 아니라 '매칭 키'다."
fi

echo
echo "==> 3) 패킷 진입점: nat 테이블 PREROUTING/OUTPUT -> KUBE-SERVICES 로 점프"
echo "    모든 서비스 트래픽은 여기서 가로채진다:"
grep -E -- '-A (PREROUTING|OUTPUT)' <<<"$NAT" | grep KUBE || true

echo
echo "==> 4) KUBE-SERVICES 에서 우리 clusterIP 매칭 규칙 찾기 (-> KUBE-SVC-*)"
grep -- '-A KUBE-SERVICES' <<<"$NAT" | grep "${CLUSTERIP}" || true
SVC_CHAIN="$(grep -- '-A KUBE-SERVICES' <<<"$NAT" | grep "${CLUSTERIP}" | grep -oE 'KUBE-SVC-[A-Z0-9]+' | head -n1)"
echo "    -> 서비스 체인: ${SVC_CHAIN:-(못 찾음: kube-proxy가 iptables 모드가 아니거나 서비스가 아직 전파 전일 수 있음)}"

echo
echo "==> 5) KUBE-SVC-* : 확률(statistic 모듈)로 엔드포인트를 분배 -> KUBE-SEP-*"
echo "    N개 엔드포인트 '균등 분배' 트릭: --probability 가 1/N, 1/(N-1), ... 마지막은 무조건(catch-all)."
if [[ -n "$SVC_CHAIN" ]]; then
  grep -- "-A ${SVC_CHAIN} " <<<"$NAT" || true
fi
SEP_CHAINS="$(grep -- "-A ${SVC_CHAIN} " <<<"$NAT" | grep -oE 'KUBE-SEP-[A-Z0-9]+' || true)"
echo "    -> 엔드포인트 체인들: ${SEP_CHAINS:-(없음)}"

echo
echo "==> 6) 각 KUBE-SEP-* : 드디어 실제 DNAT (가상 clusterIP -> 진짜 PodIP:port)"
for sep in $SEP_CHAINS; do
  echo "    [$sep]"
  grep -- "-A ${sep} " <<<"$NAT" || true
done
echo "    위 DNAT --to-destination 들이 1단계에서 본 Pod IP와 일치하는지 눈으로 대조해보라."

echo
echo "==> 7) 응답 경로 SNAT도 잠깐: 0x4000 마크 -> KUBE-POSTROUTING 에서 MASQUERADE"
grep -- '-A KUBE-MARK-MASQ' <<<"$NAT" || true
grep -- '-A KUBE-POSTROUTING' <<<"$NAT" | head -n4 || true

cat <<'EOF'

    증명 완료:
      - clusterIP는 어떤 인터페이스에도 없다(2단계). "접속 대상"이 아니라 "매칭 키"다.
      - 패킷 흐름: PREROUTING/OUTPUT -> KUBE-SERVICES(clusterIP:port로 식별, 3~4단계)
                 -> KUBE-SVC-*(확률로 하나의 엔드포인트 선택, 5단계)
                 -> KUBE-SEP-*(DNAT 로 목적지를 실제 PodIP:port로 치환, 6단계).
      => Service 오브젝트는 kube-proxy가 이 iptables 규칙을 쓰게 만드는 "선언"일 뿐,
         패킷을 직접 받는 프로세스가 아니다.  ===> "Service는 iptables 규칙이다."

    생각해볼 질문(NOTES.md):
      - 엔드포인트가 3개면 왜 첫 규칙 --probability 가 0.333이고 마지막 규칙엔 --probability 가 없나?
      - 서비스가 수천 개면 이 선형(iptables) 규칙 평가가 왜 문제인가? (IPVS/nftables/eBPF 로의 동기)

다음: bash phase-03-services/scripts/02-dns-ndots.sh
EOF
