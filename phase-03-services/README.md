# Phase 3 — 네트워킹 I: Service & DNS

> 목표: ClusterIP라는 "가상 IP"의 실체를 패킷 수준으로 이해한다. "Service는 오브젝트일 뿐, 패킷을 받는 실체가 아니다"를 iptables로 증명한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 3.

## 사전 준비

Phase 0에서 만든 멀티노드 kind 클러스터가 떠 있어야 한다 (context `kind-k8s-mastery`, worker 3대).

```bash
# 클러스터가 없으면 Phase 0부터:
bash phase-00-setup/scripts/01-create-cluster.sh

# 확인: control-plane 1 + worker 3
kubectl --context kind-k8s-mastery get nodes
docker ps --filter "name=k8s-mastery-" --format 'table {{.Names}}\t{{.Status}}'
```

이 Phase는 노드 내부(`docker exec k8s-mastery-worker ...`)로 들어가 iptables/DNS를 직접 들여다본다. 그래서 **docker에 접근할 수 있어야** 한다 (kind 노드 = Docker 컨테이너).

> 노드 컨테이너 이름: `k8s-mastery-worker`, `k8s-mastery-worker2`, `k8s-mastery-worker3` (+ `k8s-mastery-control-plane`). kind에서 노드 이름 = 컨테이너 이름.

## 실습 순서

```bash
bash phase-03-services/scripts/01-clusterip-iptables.sh        # 1. ClusterIP -> iptables NAT 체인 손으로 추적
bash phase-03-services/scripts/02-dns-ndots.sh                 # 2. DNS ndots:5 함정과 FQDN
bash phase-03-services/scripts/03-endpointslice-readiness.sh   # 3. readiness 실패 -> EndpointSlice에서 제외 관찰
bash phase-03-services/scripts/04-external-traffic-policy.sh   # 4. externalTrafficPolicy Local vs Cluster
bash phase-03-services/scripts/99-cleanup.sh                   # (끝나면) phase-03 네임스페이스 삭제
```

각 스크립트는 자기 매니페스트를 `kubectl apply`로 올리므로(idempotent) 순서를 건너뛰어도 되지만, 위 순서대로 읽는 걸 권한다. 매니페스트는 [`manifests/`](./manifests/)에 있다.

## 각 랩이 가르치는 것

- **lab 1 — ClusterIP는 iptables 규칙이다.** nginx 3개 + ClusterIP Service를 만들고, 노드 컨테이너에서 `iptables-save -t nat`을 떠서 `KUBE-SERVICES → KUBE-SVC-* → KUBE-SEP-*` 체인을 손으로 따라간다. clusterIP가 어떤 인터페이스에도 바인딩돼 있지 않음을(= 순수 매칭 키) 확인하고, KUBE-SEP의 `DNAT --to-destination`이 실제 Pod IP와 일치함을 대조한다. 엔드포인트 N개의 `--probability` 균등 분배 트릭(1/N, 1/(N-1), …, 마지막은 무조건)도 눈으로 본다.
- **lab 2 — ndots:5 함정.** Pod의 `/etc/resolv.conf`에서 `search` 도메인 + `options ndots:5`를 확인하고, 점 개수가 5 미만인 "짧은" 이름이 search 도메인으로 여러 번 확장 질의되는 것을 `dig`/`nslookup -debug`로 관찰한다. 끝점(`.`)을 붙인 FQDN이나 `dnsConfig`의 `ndots:1`로 왕복을 줄이는 법, 그리고 간헐적 DNS 지연(conntrack race)의 원인을 정리한다.
- **lab 3 — readiness와 EndpointSlice.** nginx 3개에 파일 기반 readinessProbe를 걸고, 한 Pod에서 `kubectl exec ... -- rm /tmp/ready`로 **일부러** probe를 실패시킨다. 그 endpoint가 `EndpointSlice`에서 `conditions.ready=false`로 바뀌어 서빙에서 빠지는 과정을(삭제가 아니라 '제외'임을) 관찰하고, 파일을 되살려 복귀시킨다.
- **lab 4 — externalTrafficPolicy.** 같은 백엔드에 NodePort 서비스 두 개(`Cluster` / `Local`)를 걸고, hostNetwork 클라이언트로 노드→노드 호출을 날려 `/clientip`(출발지 IP)와 `/hostname`(응답 Pod)을 비교한다. `Local`에서 소스 IP가 보존되지만 엔드포인트 없는 노드는 drop(불균형)됨을, `Cluster`에서 SNAT로 소스 IP가 치환되지만 모든 노드가 응답함을 본다. kind의 네트워킹 한계는 스크립트 주석으로 설명한다.

## ⚖️ 트레이드오프 & 대안

- **kube-proxy 모드** — **iptables**(기본): 어디서나 동작·검증됨 / 규칙 O(n) 선형 평가, 서비스 수천 개부터 갱신 지연. **IPVS**: O(1) 룩업·다양한 LB 알고리즘 / 커널 모듈 의존. **nftables**(1.33 GA): iptables의 후계·성능 개선 / 생태계 호환성 검증 중. **eBPF(kube-proxy 대체, Cilium)**: 최고 성능·관측성 / CNI 종속·러닝커브 — Phase 4에서.
- **externalTrafficPolicy Local**: 소스 IP 보존 + hop 제거 / 노드 간 불균형, 엔드포인트 없는 노드 제외 필요(LB는 healthCheckNodePort로 해결).
- **NodeLocal DNSCache**: DNS 지연·conntrack 경합 완화 / 데몬 하나 더 운영, 업그레이드 시 주의.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. "Service는 오브젝트일 뿐, 패킷을 받는 실체가 아니다"를 iptables 체인(`KUBE-SERVICES → KUBE-SVC-* → KUBE-SEP-*`)으로 증명할 수 있다.
2. 간헐적 DNS 지연(conntrack race)의 원인과 완화책(FQDN / ndots 조정 / NodeLocal DNSCache)을 설명할 수 있다.
3. `externalTrafficPolicy: Local` vs `Cluster`의 트레이드오프(소스 IP 보존 vs 균형 분배)를 설명할 수 있다.
4. (보너스) LoadBalancer 타입이 베어메탈에서 Pending인 이유와 MetalLB 같은 대안의 동작 원리를 설명할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.

끝나면 `99-cleanup.sh`로 `phase-03` 네임스페이스를 지운다 (클러스터 자체는 Phase 0 소유라 유지).
