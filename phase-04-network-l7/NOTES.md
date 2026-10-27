# Phase 4 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] Cilium을 CNI로 설치 (`01`) — kube-proxy replacement 모드, Hubble 활성화
- [ ] Gateway API 경로/가중치 라우팅 (`02`)
- [ ] default-deny → DNS 장애 관찰 → 수정 (`03`)
- [ ] (선택) Cilium WireGuard / mTLS 안내 (`04`)

## 2. 관찰한 증상 (사실만)

### lab 1 — Cilium / kube-proxy replacement
- Cilium 설치 '전' 노드 상태: ______ (예: NotReady — 왜? ______)
- `cilium-dbg status | grep KubeProxyReplacement` 결과: ______ (True?)
- `k8sServiceHost`에 넣은 값: ______:6443 (이 값이 왜 `kubectl cluster-info`의 127.0.0.1:xxxx와 다른가? ______)
- Hubble로 본 플로우 한 줄 예시: ______

### lab 2 — Gateway API
- `kubectl get gatewayclass` 의 ACCEPTED: ______
- `GET /v1` → ______ / `GET /v2` → ______
- `/split` 20회 결과 (v1:v2): ______ : ______  (90/10에 가까운가? ______)

### lab 3 — NetworkPolicy
| 단계 | nslookup(이름) | curl by 이름 | curl by IP |
|---|---|---|---|
| 정책 없음 (기준선) | ______ | ______ | ______ |
| default-deny 후 | ______ | ______ | ______ |
| allow-app-no-dns 후 | ______ | ______ | ______ |
| allow-dns 후 | ______ | ______ | ______ |

- `allow-app-no-dns` 단계에서 **IP로는 되는데 이름으론 안 된** 이유(내 설명):
  > ______ (키워드: egress 53, kube-dns, 명세≠집행)
- Hubble `--verdict DROPPED`로 본 드롭 플로우: ______

### lab 4 (선택) — 암호화/인증
- `cilium status`의 Encryption: ______ (Wireguard?)

## 3. 원인 가설과 검증
- kube-proxy가 없는데도 ClusterIP Service가 동작하는 이유(내 설명):
  > ______ (힌트: eBPF가 소켓/‑패킷 레벨에서 LB, kube-proxy의 iptables/IPVS를 대체)
- NetworkPolicy를 적용했는데 Flannel 단독 클러스터였다면 어떻게 됐을까?
  > ______ (힌트: 집행자 = CNI. 지원 안 하면 '명세'는 있어도 '집행'이 없다)

## 4. 배운 트레이드오프
- CNI: Cilium vs Calico vs Flannel vs 클라우드 CNI — 내 상황엔 ______ . 이유: ______
- 오버레이(VXLAN) vs 네이티브 라우팅 — ______ 선택의 비용: ______
- 메시 도입 여부 — 내 조직엔 ______ . 근거: ______

## 5. 완료 기준 — 질문에 답하기

**Q1. NetworkPolicy는 "누가 / 어느 레이어에서" 집행하는가?**
> ______
> (키워드: 명세=API 오브젝트, 집행=CNI 데이터패스(Cilium eBPF), 지원 안 하는 CNI면 무시)

**Q2. Gateway API가 Ingress의 설계 결함을 고친 지점 3가지는?**
1. ______ (힌트: 역할 분리 — GatewayClass/Gateway/HTTPRoute)
2. ______ (힌트: 어노테이션 지옥 → 표준 필드: 가중치/헤더매칭/미러링)
3. ______ (힌트: 포트폴리오/리스너 소유권, 네임스페이스 교차 라우팅 제어)

**Q3. "서비스 메시가 필요 없다"를 근거 3개로 방어하라. 반대로 필요한 신호는?**
- 필요 없다는 근거: ① ______ ② ______ ③ ______
- 도입 신호: ______ (예: 서비스 수 급증, 규제상 전구간 mTLS 의무, 세밀한 트래픽 제어 요구)

---
_다음 Phase로 넘어가기 전에 Q1~Q3을 막힘없이 답할 수 있는지 확인._
