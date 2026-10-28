#!/usr/bin/env bash
# Phase 3 / lab 2 — DNS ndots:5 함정과 FQDN
# 질문: 왜 짧은 이름 조회가 DNS 서버에 '여러 번' 질의로 번지는가? 어떻게 줄이는가?
# 실행: bash phase-03-services/scripts/02-dns-ndots.sh
#
# 관찰 랩이라 -e 미사용. exec/dig/nslookup/grep 이 상황에 따라 non-zero를 낼 수 있어
# 각 단계를 || true 로 흘려보낸다. (조회 대상 clusterip-demo 서비스도 함께 apply 해 둔다.)
set -uo pipefail

CTX="kind-k8s-mastery"
NS="phase-03"
CLIENT="dnsutils"
SVC="clusterip-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"

echo "==> 0) 조회 대상 서비스(lab1) + DNS 디버깅 클라이언트(jessie-dnsutils) 배포"
kubectl --context "$CTX" apply -f "${MANIFESTS}/00-namespace.yaml"
kubectl --context "$CTX" apply -f "${MANIFESTS}/01-clusterip.yaml"   # 조회가 NOERROR 나오도록 대상 확보
kubectl --context "$CTX" apply -f "${MANIFESTS}/02-dns-client.yaml"
kubectl --context "$CTX" -n "$NS" wait --for=condition=Ready pod/"$CLIENT" --timeout=120s

# 클라이언트 Pod 안에서 명령 실행하는 짧은 래퍼
K() { kubectl --context "$CTX" -n "$NS" exec "$CLIENT" -- "$@"; }

echo
echo "==> 1) Pod의 /etc/resolv.conf — ndots:5 와 search 도메인"
K cat /etc/resolv.conf || true
cat <<'EOF'

    핵심 해석:
      search phase-03.svc.cluster.local svc.cluster.local cluster.local
      nameserver 10.96.0.10            # kube-dns(CoreDNS)의 ClusterIP
      options ndots:5
    ndots:5 규칙 = "질의 이름의 점(.) 개수가 5개 미만이면, 그 이름을 absolute로 보지 않고
    search 도메인을 하나씩 붙여 먼저 시도한 뒤, 그래도 안 되면 마지막에 이름 그대로 질의한다."
EOF

echo
echo "==> 2) '짧은' 이름일수록 search로 번진다 — 1점짜리 이름의 후보들을 dig로 하나씩 재현"
echo "    (clusterip-demo.phase-03 = 점 1개 < 5 -> 아래 순서로 시도되고, 첫 후보는 낭비(NXDOMAIN))"
for q in \
  "clusterip-demo.phase-03.phase-03.svc.cluster.local." \
  "clusterip-demo.phase-03.svc.cluster.local." ; do
  printf "    %-52s -> " "$q"
  K dig +time=2 +tries=1 +noall +comments +answer "$q" A 2>/dev/null \
    | grep -E 'status:|IN[[:space:]]+A' | tr '\n' ' ' || true
  echo
done
echo "    => 첫 후보가 NXDOMAIN이면 그만큼 '왕복 낭비'. 외부 도메인(foo.com, 점 1개)은"
echo "       search 3개를 전부 헛돌고 4번째(foo.com.)에서야 해석된다 = 3회 낭비."

echo
echo "==> 3) nslookup -debug 로 '실제' 질의 흐름 관찰 (resolver가 search를 직접 적용)"
echo "    짧은 이름 'clusterip-demo.phase-03' 조회 시 NXDOMAIN 시도 + 성공 응답이 함께 보인다:"
K nslookup -debug clusterip-demo.phase-03 2>&1 \
  | grep -E 'Query|QUESTIONS|->|Name:|Address|status|NXDOMAIN|SERVFAIL|AUTHORITY' \
  | head -n 40 || true

echo
echo "==> 4) FQDN(끝에 점!)으로 질의하면 search 확장 없이 '한 방'에 끝난다"
echo "    ${SVC}.${NS}.svc.cluster.local.   <- 맨 끝 '.'이 absolute(완전수식) 표시"
K dig +noall +comments +answer "${SVC}.${NS}.svc.cluster.local." A 2>/dev/null \
  | grep -E 'status:|IN[[:space:]]+A' || true
cat <<EOF

    함정(중요): FQDN이라도 '끝점(.)'이 없고 점이 4개뿐이면
               (예: ${SVC}.${NS}.svc.cluster.local  <- 점 4개)
               4 < ndots(5) 라서 '여전히' search 확장을 먼저 시도한다.
    => 확실히 줄이려면:
       (a) 이름 끝에 '.' 을 붙여 absolute 로,  또는
       (b) Pod spec 의 dnsConfig.options 로 ndots:1 지정(레이턴시 민감 앱),  또는
       (c) 코드/설정에 FQDN을 박아두기.
    실제 질의 횟수를 서버 쪽에서 세고 싶으면: CoreDNS Corefile에 'log' 플러그인을 추가하고
       (kubectl -n kube-system edit configmap coredns) CoreDNS 로그를 보면 질의 라인이 그대로 찍힌다.
EOF

cat <<'EOF'

    결론:
      - ndots:5는 "클러스터 내부 짧은 이름 조회 편의"를 위해 search를 공격적으로 붙인다.
        대가로 외부 도메인/부분 수식 이름이 불필요한 왕복(특히 NXDOMAIN 캐싱 전)을 만든다.
      - 완화: FQDN(끝점) 사용 / dnsConfig로 ndots 조정 / NodeLocal DNSCache.
      - "간헐적 DNS 지연"의 고전 원인: conntrack race(동시 UDP 질의의 DNAT 경합) + UDP
        재전송 타임아웃(기본 5s) -> 꼬리 지연. 완화책이 NodeLocal DNSCache / single-request 옵션.
        (Phase 3 완료 기준 질문 중 하나 — NOTES.md에서 스스로 설명해보라.)

다음: bash phase-03-services/scripts/03-endpointslice-readiness.sh
EOF
