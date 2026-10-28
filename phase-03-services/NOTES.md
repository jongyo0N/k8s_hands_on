# Phase 3 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상(사실만) ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸(______)은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] lab 1 — ClusterIP + iptables NAT 체인 추적 (`01`)
- [ ] lab 2 — DNS ndots:5 관찰 + FQDN (`02`)
- [ ] lab 3 — readiness 실패 -> EndpointSlice 제외 관찰 (`03`)
- [ ] lab 4 — externalTrafficPolicy Local vs Cluster (`04`)

## 2. 관찰한 증상 (사실만)

### lab 1 — iptables 체인
```
clusterIP                 = ______
KUBE-SERVICES 매칭 규칙    -> KUBE-SVC-______
KUBE-SVC-* 의 엔드포인트   -> KUBE-SEP-______ , KUBE-SEP-______ , KUBE-SEP-______
각 KUBE-SEP-* 의 DNAT      --to-destination ______:80 , ______:80 , ______:80
```
- `ip addr`에 clusterIP가 보였는가? ______ (예/아니오)
- 엔드포인트 3개일 때 첫 규칙의 `--probability` 값 = ______ , 마지막 규칙엔 왜 없나? ______

### lab 2 — resolv.conf & 질의 횟수
```
search  = ______
nameserver = ______
options = ndots:______
```
- 짧은 이름(`clusterip-demo.phase-03`) 조회 시 NXDOMAIN 시도 횟수: ______
- FQDN(끝점 `.`) 조회 시 질의 횟수: ______
- 점 4개(`...svc.cluster.local`, 끝점 없음)는 왜 여전히 확장되나? ______

### lab 3 — readiness 전파
- `/tmp/ready` 삭제 후 victim이 NotReady 되기까지 걸린 시간(대략): ______ 초
- EndpointSlice에서 victim endpoint의 `conditions.ready` 값: ______
- victim 주소가 슬라이스에서 '삭제'됐나, 아니면 'ready=false로 남았나'? ______

### lab 4 — externalTrafficPolicy
```
                Cluster 정책                 Local 정책
응답한 노드      ______                       ______ (엔드포인트 있는 노드만?)
seen-client-ip  ______ (SNAT? 노드 IP?)       ______ (보존? 호출자 IP?)
드롭된 노드      ______                       ______
```

## 3. 원인 가설과 검증

- "Service는 iptables 규칙일 뿐"을 내 말로:
  > ______ (clusterIP가 인터페이스에 없다는 사실 + KUBE-SERVICES→SVC→SEP→DNAT 흐름으로)

- ndots:5가 외부 도메인 조회를 느리게 만드는 이유:
  > ______ (search 3개 + 자기 자신 = 최대 4회 왕복, NXDOMAIN 캐싱 전)

- readiness 실패가 트래픽을 끊는 경로(컨트롤러/프록시 관점):
  > ______ (kubelet -> Ready=false -> EndpointSlice ready=false -> kube-proxy가 SEP 제외)

- Local 정책이 소스 IP를 보존하는 이유(SNAT가 왜 없나):
  > ______ (로컬 엔드포인트로만 보내 hop이 없고, hop이 없으니 마스커레이드 불필요)

## 4. 배운 트레이드오프
- kube-proxy 모드: iptables vs IPVS vs nftables vs eBPF — 내 상황에선 ______ . 이유: ______
- externalTrafficPolicy: Local을 쓰면 얻는 것 ______ / 잃는 것 ______
- DNS: FQDN 강제 vs NodeLocal DNSCache — 각각 언제? ______

## 5. 완료 기준 — 질문에 답하기

**Q1. "Service는 패킷을 받는 실체가 아니다"를 iptables로 증명하라.**
> ______ (체인 이름과 DNAT를 근거로)

**Q2. 간헐적 DNS 지연(conntrack race)의 원인과 완화책은?**
> ______ (동시 UDP 질의의 DNAT 경합 + UDP 재전송 타임아웃 / NodeLocal DNSCache·single-request·FQDN)

**Q3. externalTrafficPolicy Local vs Cluster의 트레이드오프는?**
> ______

**Q4. (보너스) LoadBalancer 타입이 베어메탈에서 왜 Pending이고, MetalLB는 어떻게 해결하나?**
> ______ (클라우드 LB 프로비저너 부재 / MetalLB가 L2(ARP)·BGP로 외부 IP 광고)

---
_다음 Phase로 넘어가기 전에 Q1~Q4를 막힘없이 답할 수 있는지 확인._
