# Phase 4 — 네트워킹 II: Gateway API · CNI · NetworkPolicy · 메시

> 목표: L7 라우팅과 클러스터 네트워크 레이어를 **설계·선택**할 수 있다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 4.

이 Phase는 네트워크 스택을 **직접 갈아끼우며** 배운다: 기본 CNI와 kube-proxy를 빼고
Cilium(eBPF)으로 대체한 뒤, 그 위에서 Gateway API·NetworkPolicy·(선택)mTLS를 얹는다.

## 사전 준비

```bash
bash phase-04-network-l7/scripts/00-check-tools.sh
```

필수: `docker` · `kind` · `kubectl` · `helm`. 권장(선택): `cilium` CLI, `hubble` CLI.

```bash
brew install kind kubectl helm
brew install cilium-cli hubble   # 선택: cilium status / hubble observe 용
```

### 왜 전용 클러스터인가 (`kind-cilium.yaml`)

Phase 0의 `k8s-mastery`와 **별개의 전용 클러스터**(`k8s-l7`)를 쓴다. CNI/kube-proxy를
직접 교체하기 때문에 깨끗한 클러스터가 필요하다. 설정의 핵심 두 줄:

```yaml
networking:
  disableDefaultCNI: true   # kindnet 안 깖 → 설치 직후 노드 NotReady (Cilium이 채운다)
  kubeProxyMode: "none"     # kube-proxy 안 깖 → Service 처리를 Cilium이 대신 (replacement)
```

> ⚠️ kube-proxy replacement의 Socket LB는 호스트 커널/‑cgroup 요건이 있다(cgroup v2 +
> 커널 5.14+ 권장). Docker Desktop/OrbStack/Colima 최신 VM은 대개 충족한다. 미충족 시
> Cilium agent가 뜨지 않으면 [kubeproxy-free 문서](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)를 확인.

## 실습 순서

```bash
bash phase-04-network-l7/scripts/00-check-tools.sh          # 0. 도구 점검
bash phase-04-network-l7/scripts/01-install-cilium.sh       # 1. 클러스터 생성 + Cilium(CNI, kube-proxy replacement) + Hubble
bash phase-04-network-l7/scripts/02-gateway-api.sh          # 2. Gateway API CRD + 경로/가중치 라우팅
bash phase-04-network-l7/scripts/03-netpol-default-deny.sh  # 3. default-deny → DNS 장애 관찰 → 수정
bash phase-04-network-l7/scripts/04-mtls.sh                 # 4. (선택) Cilium WireGuard/mTLS 안내
bash phase-04-network-l7/scripts/99-cleanup.sh              # (끝나면) 클러스터 삭제
```

버전을 고정/변경하려면 (스크립트에 핀 되어 있음, 아래는 재정의 예):

```bash
CILIUM_VERSION=1.20.4 GWAPI_VERSION=v1.6.3 \
  bash phase-04-network-l7/scripts/02-gateway-api.sh
```

## 각 랩이 가르치는 것

- **lab 1 — Cilium CNI + kube-proxy replacement + Hubble.**
  CNI의 역할 경계(Pod IP 할당·노드 간 라우팅)와, 원래 kube-proxy가 하던 Service 처리를
  Cilium eBPF가 어떻게 흡수하는지. kube-proxy가 없어 `kubernetes` ClusterIP를 아직 못 뚫는
  부트스트랩 문제 → `k8sServiceHost`로 API server 실주소를 직접 넘기는 이유를 체감.
  Hubble로 플로우를 눈으로 관측한다(관측성 = Cilium의 강점).
- **lab 2 — Gateway API.**
  Ingress의 설계 결함(어노테이션 과다, 역할 미분리)을 Gateway API가 어떻게 고쳤는지:
  `GatewayClass`(구현체) / `Gateway`(리스너) / `HTTPRoute`(규칙)의 **역할 분리**. 경로 기반
  라우팅과 가중치 90/10 트래픽 분할(카나리)을 **표준 필드**로 구성한다(Cilium Gateway 구현체).
- **lab 3 — default-deny NetworkPolicy.**
  "기본 allow-all의 함정" → default-deny → 필요한 것만 허용. **DNS egress를 일부러 빼서**
  "앱은 열었는데 이름 해석이 안 되는" 전형적 장애를 관찰하고 고친다. 그리고 "집행자는 CNI"임을
  (NetworkPolicy는 명세일 뿐, 실제 차단은 Cilium eBPF가 함) 확인한다.
- **lab 4 (선택) — 메시 없이 암호화/인증만.**
  Cilium WireGuard 투명 암호화로 "mTLS만 필요하면 메시 없이도 된다"를 체감. 신원 기반 상호
  인증(Cilium mutual auth/SPIFFE) 및 Istio ambient는 매니페스트로 안내만 제공.

## ⚖️ 트레이드오프 & 대안

- **CNI 선택**: Cilium(eBPF, L7 정책·관측성·성능, CNCF graduated / 러닝커브) vs
  Calico(성숙·BGP·대규모 검증 / eBPF는 후발) vs Flannel(단순 / NetworkPolicy 단독 미지원) vs
  클라우드 CNI(VPC 네이티브 / IP 고갈). 오버레이(VXLAN) vs 네이티브 라우팅(BGP/클라우드 라우트).
- **Ingress 유지 vs Gateway API 이행**: 기존 자산·도구 호환 vs 표준의 방향성. 신규는 Gateway API.
  (⚠️ ingress-nginx는 2026년 3월 유지보수 종료 예정 — 신규 학습은 Gateway API 구현체 중심.)
- **메시 도입 자체가 트레이드오프**: mTLS·세밀한 트래픽 제어·일관된 텔레메트리 ↔ 운영 복잡도·
  리소스 오버헤드·업그레이드 리스크. mTLS만 필요하면 Cilium WireGuard/SPIFFE로 충분할 때가 많다.
- **sidecar vs ambient**: 격리·성숙도 vs 리소스 효율·운영 단순화(ambient는 상대적으로 신규).

## 완료 기준 (NOTES.md에 답을 적을 것)

1. NetworkPolicy가 "누구에 의해, 어느 레이어에서" 집행되는지 설명할 수 있다.
2. Gateway API가 Ingress의 어떤 설계 결함을 어떻게 고쳤는지 3가지를 댈 수 있다.
3. "우리 조직엔 서비스 메시가 필요 없다"를 근거 3개로 방어하고, 반대로 필요한 시점의 신호도 댄다.

## 검증 수준 (중요)

이 레포의 매니페스트/스크립트는 **문법 검증**(`bash -n`, YAML 파싱)을 거쳤다. 다만:

- `manifests/gateway/*`(Gateway/HTTPRoute), `manifests/mtls/cilium-mutual-auth.yaml`은
  **CRD가 설치된 실클러스터에서만** `kubectl apply` 스키마 검증이 가능하다(CRD 설치 전에는
  클라이언트 검증 불가). lab 02 스크립트가 CRD를 먼저 깐 뒤 적용한다.
- `kind-cilium.yaml`의 kube-proxy replacement는 호스트 커널/‑cgroup에 의존 → 환경에 따라 결과가 다를 수 있다.
- `90-lb-ippool.yaml`의 CIDR는 로컬 kind 도커 네트워크에 맞춰 바꿔야 한다(기본 검증 경로는 port-forward).

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.
