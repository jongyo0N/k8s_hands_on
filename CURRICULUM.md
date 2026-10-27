# Kubernetes 마스터 커리큘럼 — 실무자용

> 대상: 컨테이너/리눅스 기본기가 있는 실무 엔지니어.
> 목표: "쓸 줄 아는" 수준을 넘어 **내부 동작을 설명하고, 설계 결정을 트레이드오프로 방어하고, 프로덕션 장애를 체계적으로 디버깅**하는 수준.
> 분량: 14개 Phase, 주당 6~10시간 기준 약 4~5개월 (전일 투자 시 7~9주).

---

## 설계 원칙

1. **Internals 우선** — 아키텍처와 reconciliation 모델을 먼저 잡고 리소스 종류는 그 위에 얹는다. 실무자는 "어떻게 쓰나"보다 "왜 이렇게 동작하나"가 병목이다.
2. **모든 선택은 트레이드오프** — 각 Phase에 `⚖️ 트레이드오프 & 대안` 섹션이 있다. 기술 선택에 정답은 없고, 방어 가능한 결정만 있다.
3. **만들고 관찰하며 배운다** — 각 랩은 ①정상 구성을 만들고 ②의도된 결함 조건을 넣어보고 ③증상에서 원인을 역추적하는 순서다. 운영 역량은 3번에서 나온다.
4. **설명 가능 = 완료** — 각 Phase의 "완료 기준"은 시니어 면접 수준의 질문이다. 남에게 설명 못 하면 끝난 게 아니다.

### 학습 루프 (공통)

```
읽기(공식 문서·KEP) → 만들기(랩) → 관찰·검증(조건 바꿔보기) → 설명하기(완료 기준 질문에 답)
```

- 랩 산출물은 이 레포에 `phase-XX-<topic>/` 디렉토리로 남긴다 (매니페스트 + `NOTES.md`). 끝나면 그 자체가 포트폴리오다.
- 버전 표기: 괄호 안 버전은 해당 기능이 안정화(GA)되거나 기본 활성화된 대략의 지점. 최신 상태는 공식 문서로 재확인한다.

---

## 로드맵 요약

| Phase | 주제 | 기간 | 대표 트레이드오프 |
|---|---|---|---|
| 0 | 환경 구축 & 도구 | 0.5주 | kind vs minikube vs k3d |
| 1 | 아키텍처 & 선언적 모델 | 1주 | 선언적 vs 명령적, level vs edge triggered |
| 2 | 워크로드 & Pod 심화 | 1.5주 | 배포 전략 4종, probe 공격성 |
| 3 | 네트워킹 I — Service & DNS | 1주 | kube-proxy 모드 3종 |
| 4 | 네트워킹 II — Gateway API, CNI, 메시 | 1.5주 | CNI 3종, 메시 도입 여부 |
| 5 | 스토리지 | 1주 | DB on k8s vs 매니지드 DB |
| 6 | 구성·시크릿·패키징 | 1주 | Helm vs Kustomize, 시크릿 관리 4종 |
| 7 | 스케줄링 & 오토스케일링 | 1.5주 | CPU limit 논쟁, CA vs Karpenter |
| 8 | 보안 & 하드닝 | 1.5주 | 정책 엔진 3종, 런타임 격리 수준 |
| 9 | 관측성 | 1주 | self-hosted vs managed, Loki vs ES |
| 10 | 클러스터 수명주기 & 운영 | 1.5주 | managed vs self-managed, 업그레이드 전략 |
| 11 | 확장 — CRD·Operator·API 내부 | 1.5주 | operator 프레임워크 선택, webhook 리스크 |
| 12 | GitOps & 배포 파이프라인 | 1주 | Argo CD vs Flux vs CI push |
| 13 | 프로덕션 심화 & 캡스톤 | 2주 | 비용 vs 안정성, 규모의 한계 |

자격증 매핑: Phase 0~7 ≈ **CKA/CKAD**, Phase 8 ≈ **CKS**, Phase 10~11 ≈ 그 이상.

---

## Phase 0 — 환경 구축 & 도구 (0.5주)

**목표**: 1분 안에 멀티노드 클러스터를 만들고 지울 수 있는 로컬 환경.

**핵심 주제**
- 로컬 클러스터: kind 멀티노드 구성, 클러스터 설정 파일(`kind-config.yaml`)
- kubeconfig 구조 (clusters/users/contexts), 멀티 클러스터 전환
- 도구 체인: `kubectl` + krew 플러그인(`ctx`, `ns`, `neat`, `tree`), `k9s`, `stern`, `helm`, `kustomize`, `jq`/`yq`

**랩** (`phase-00-setup/`)
1. kind로 control-plane 1 + worker 3 클러스터 생성, 노드별 label 부여
2. kubeconfig를 직접 열어 인증 체인 확인 (어떤 자격증명으로 누가 인증되는가)
3. 관찰: control-plane 컨테이너를 중지했을 때 kubectl 응답과 기존 Pod 상태가 어떻게 달라지는지

**⚖️ 트레이드오프 & 대안**
- **kind** (추천): 멀티노드·CI 친화·업스트림과 동일 바이너리 / 단점: LoadBalancer 등 클라우드 기능 없음(cloud-provider-kind로 보완)
- **minikube**: 애드온 풍부, VM 드라이버로 더 "진짜" 노드 / 단점: 멀티노드가 부자연스러움, 무거움
- **k3d**: 가장 가볍고 빠름 / 단점: k3s 기반이라 업스트림과 미세한 차이(내장 Traefik, SQLite 옵션 등)
- macOS 런타임: Docker Desktop(대기업 유료) vs OrbStack(빠름, 상용 유료) vs Colima(무료 OSS, 설정 수동)
- 클라우드 실습(EKS/GKE)은 Phase 7, 10에서만 — 비용 대비 로컬로 90% 커버 가능

**완료 기준**
- kubeconfig의 user 인증 방식 3가지(클라이언트 인증서, 토큰, exec 플러그인)를 설명할 수 있다
- control-plane이 내려가도 기존 Pod가 계속 도는 이유를 말할 수 있다

---

## Phase 1 — 아키텍처 & 선언적 모델 (1주)

**목표**: `kubectl apply` 이후 일어나는 일을 컴포넌트 단위로 끝까지 설명한다. 이 멘탈 모델이 이후 전부의 기반.

**핵심 주제**
- 컴포넌트: kube-apiserver(유일한 etcd 접점), etcd(raft 합의), kube-scheduler, kube-controller-manager, kubelet, kube-proxy, CRI(containerd)
- 선언적 모델: spec vs status, reconciliation loop, watch 메커니즘(HTTP streaming + resourceVersion)
- API 요청 파이프라인: 인증 → 인가 → admission(mutating → validating) → validation → etcd 저장
- 컨트롤러 패턴: desired state로 수렴, 실패 시 backoff 재시도
- Pod 생성 전체 흐름: apply → Deployment controller → ReplicaSet controller → scheduler binding → kubelet → CRI → CNI → 컨테이너 기동

**랩** (`phase-01-architecture/`)
1. `kubectl get --raw`, `-v=9`로 API 호출을 직접 관찰. `kubectl proxy`로 API 탐색
2. `etcdctl`로 저장된 오브젝트를 열어본다 (protobuf 직렬화 확인)
3. 관찰: scheduler를 멈춘 뒤 Pod를 만들면 Pending에 머무는 것, `nodeName`을 직접 지정하면 뜨는 것 → scheduler의 실제 역할 확인
4. 관찰: etcd 응답 지연이 생겼을 때 API 응답이 어떻게 변하는지

**⚖️ 트레이드오프 & 대안**
- **선언적 + level-triggered**: 이벤트 유실에 강하고 자가 치유 / 비용: 변화 감지의 지연, "왜 아직 반영 안 됐나"의 디버깅 난도. edge-triggered(이벤트 기반)는 즉각적이지만 유실 시 영구 불일치
- **etcd(raft, 강한 일관성)**: 정합성 보장 / 비용: 쓰기 성능 한계, 디스크 지연에 민감. 대안: k3s의 SQLite/kine(소규모) — 그러나 watch 시맨틱 호환이 핵심 제약
- **모놀리식 API server**: 단일 진입점이라 정책·감사 일원화 / 비용: 스케일 병목이자 SPOF — 그래서 HA는 "복제"로 푼다

**완료 기준**
- `kubectl apply` → 컨테이너 기동까지 등장하는 컴포넌트 7개와 각자의 역할을 순서대로 설명
- etcd 디스크가 느려지면 나타나는 증상 체인을 설명 (watch 지연 → 컨트롤러 반응 지연 → …)
- resourceVersion과 optimistic concurrency가 동시 수정 충돌을 어떻게 막는지 설명

---

## Phase 2 — 워크로드 & Pod 심화 (1.5주)

**목표**: 워크로드 컨트롤러를 상황에 맞게 선택하고, 무중단 배포·우아한 종료를 실제로 보장한다.

**핵심 주제**
- Pod lifecycle: phase vs conditions, init container, **native sidecar**(restartPolicy: Always, 1.33 GA), ephemeral container
- Probes 심화: liveness/readiness/startup의 각기 다른 목적, 잘못된 liveness가 일시 과부하를 재시작 폭풍으로 증폭시키는 메커니즘
- Graceful shutdown: SIGTERM → preStop → terminationGracePeriodSeconds, 종료 중에도 트래픽이 오는 레이스(엔드포인트 전파 지연)와 해법
- Deployment: rollout 내부 동작(ReplicaSet 2개의 줄다리기), maxSurge/maxUnavailable, revision history, rollback
- StatefulSet: ordinal 보장, PVC template, headless service 연계 — 그리고 "순서 보장"의 한계
- DaemonSet, Job(parallelism/completions/podFailurePolicy/backoffLimitPerIndex), CronJob(동시성 정책, 시간대)

**랩** (`phase-02-workloads/`)
1. 느리게 시작하는 앱에 startup probe 없이 liveness만 걸었을 때의 CrashLoop를 재현하고, 올바르게 수정
2. 부하 중 rolling update에서 5xx가 0이 되도록 preStop + readiness + 종료 핸들러 조합을 튜닝
3. StatefulSet으로 3노드 분산 앱(예: redis) 배포, Pod 강제 삭제 시 identity 유지 확인
4. Job의 podFailurePolicy로 "재시도할 실패 vs 즉시 포기할 실패"를 구분 처리

**⚖️ 트레이드오프 & 대안**
- **배포 전략**: rolling(기본, 리소스 효율) vs recreate(단순, 다운타임) vs blue-green(즉시 롤백, 2배 리소스) vs canary(리스크 최소, 파이프라인 복잡도) — canary는 Phase 12의 Argo Rollouts에서 실습
- **liveness probe**: 데드락 자동 복구 / 비용: 일시 과부하를 재시작 폭풍으로 증폭. 보수적 운영: liveness를 빼고 readiness만 — 외부 의존성 체크는 절대 liveness에 넣지 않는다
- **StatefulSet vs Deployment+PVC vs Operator**: 안정적 identity가 필요한가? 복제·failover 로직까지 필요하면 StatefulSet만으로 부족 → operator(Phase 5, 11)
- **native sidecar vs 일반 sidecar 컨테이너**: 시작/종료 순서 보장, Job 종료 문제 해결 / 구버전 클러스터 호환성 확인 필요

**완료 기준**
- readiness와 liveness 각각이 실패했을 때 일어나는 일의 차이를 컴포넌트 수준으로 설명
- SIGTERM 이후에도 요청이 들어오는 이유(엔드포인트 전파의 비동기성)와 완화책 3가지
- StatefulSet이 보장하는 것과 보장하지 않는 것(데이터 복제, 리더 선출)을 구분

---

## Phase 3 — 네트워킹 I: Service & DNS (1주)

**목표**: ClusterIP라는 "가상 IP"의 실체를 패킷 수준으로 이해한다.

**핵심 주제**
- Service 타입: ClusterIP / NodePort / LoadBalancer / ExternalName, headless service
- EndpointSlice (Endpoints API는 deprecated), 엔드포인트 전파 경로
- kube-proxy 동작: iptables 모드의 NAT 체인 추적, IPVS, nftables 모드(1.33 GA)
- CoreDNS: 서비스 디스커버리, `ndots:5` 문제와 FQDN, NodeLocal DNSCache
- 트래픽 정책: externalTrafficPolicy(Local vs Cluster), internalTrafficPolicy, Topology Aware Routing
- 접근 경로 정리: hostPort/hostNetwork/port-forward/NodePort/LB의 차이

**랩** (`phase-03-services/`)
1. ClusterIP 서비스를 만들고 노드에서 `iptables-save`로 NAT 체인을 손으로 추적 (KUBE-SERVICES → KUBE-SVC-* → KUBE-SEP-*)
2. DNS 쿼리를 tcpdump로 캡처해 ndots로 인한 불필요한 조회를 확인 → FQDN으로 수정
3. 관찰: 특정 Pod만 readiness를 실패시켜 EndpointSlice에서 빠지는 과정
4. externalTrafficPolicy: Local로 소스 IP 보존을 확인하고, 노드 간 불균형 분배를 관찰

**⚖️ 트레이드오프 & 대안**
- **iptables**(기본): 어디서나 동작, 검증됨 / O(n) 규칙 평가, 서비스 수천 개부터 갱신 지연. **IPVS**: O(1) 룩업, 다양한 LB 알고리즘 / 커널 모듈 의존. **nftables**: iptables의 후계, 성능 개선 / 생태계 호환성 검증 중. **eBPF(kube-proxy 대체, Cilium)**: 최고 성능·관측성 / CNI 종속, 러닝커브 — Phase 4에서
- **externalTrafficPolicy Local**: 소스 IP 보존, hop 제거 / 노드 간 불균형, 엔드포인트 없는 노드 제외 필요
- **NodeLocal DNSCache**: DNS 지연·conntrack 경합 완화 / 데몬 하나 더 운영, 업그레이드 시 주의

**완료 기준**
- "Service는 오브젝트일 뿐, 패킷을 받는 실체가 아니다"를 iptables 체인으로 증명
- 간헐적 DNS 지연(conntrack race)의 원인과 완화책을 설명
- LoadBalancer 타입이 베어메탈에서 Pending인 이유와 MetalLB 같은 대안의 동작 원리

---

## Phase 4 — 네트워킹 II: Gateway API, CNI, NetworkPolicy, 메시 (1.5주)

**목표**: L7 라우팅과 클러스터 네트워크 레이어를 설계·선택할 수 있다.

**핵심 주제**
- Ingress의 구조적 한계(어노테이션 과다, 역할 미분리) → **Gateway API**(GA): GatewayClass/Gateway/HTTPRoute의 역할 분리 모델
  - ⚠️ **ingress-nginx는 2026년 3월로 유지보수 종료(retired)**. 신규 학습·도입은 Gateway API 구현체 중심으로 (Envoy Gateway, Cilium Gateway, Traefik, NGINX Gateway Fabric 등)
- CNI의 역할 경계: Pod IP 할당·노드 간 라우팅 (Service는 CNI 소관이 아님 — kube-proxy와의 분업)
- 오버레이(VXLAN) vs 네이티브 라우팅(BGP/클라우드 라우트)
- NetworkPolicy: 기본 allow-all의 함정, default-deny 패턴, 네임스페이스 격리, "집행자는 CNI"
- Service mesh: mTLS, 트래픽 분할, 재시도/타임아웃 — sidecar 모델 vs Istio ambient(sidecarless), Linkerd, Cilium mesh

**랩** (`phase-04-network-l7/`)
1. kind에서 Cilium을 CNI로 설치(kube-proxy replacement 모드), Hubble로 플로우 관측
2. Gateway API로 호스트/경로 기반 라우팅 + 가중치 기반 트래픽 분할(90/10) 구성
3. default-deny NetworkPolicy를 깐 뒤 필요한 통신만 하나씩 허용 — DNS egress 누락으로 생기는 장애를 관찰·수정
4. (선택) Istio ambient 설치, mTLS 확인 후 "메시가 준 것 vs 가져간 것" 기록

**⚖️ 트레이드오프 & 대안**
- **CNI 선택**: Cilium(eBPF, L7 정책·관측성·성능, CNCF graduated / 러닝커브) vs Calico(성숙·BGP·대규모 검증 / eBPF 기능은 후발) vs Flannel(단순 / NetworkPolicy 단독 미지원) vs 클라우드 CNI(VPC 네이티브, IP 고갈 이슈)
- **Ingress 유지 vs Gateway API 이행**: 기존 자산·도구 호환 vs 표준의 방향성. 신규는 Gateway API가 기본값
- **메시 도입 자체가 트레이드오프**: mTLS·세밀한 트래픽 제어·일관된 텔레메트리 / 비용: 운영 복잡도, 리소스 오버헤드, 업그레이드 리스크. 대안: mTLS만 필요하면 Cilium WireGuard/SPIFFE, 재시도·타임아웃은 앱 라이브러리로 — "메시 없이 버티기"가 정답인 조직이 많다
- **sidecar vs ambient**: 격리·성숙도 vs 리소스 효율·운영 단순화(ambient는 상대적으로 신규)

**완료 기준**
- NetworkPolicy가 "누구에 의해, 어느 레이어에서" 집행되는지 설명
- Gateway API가 Ingress의 어떤 설계 결함을 어떻게 고쳤는지 3가지
- "우리 조직에 서비스 메시가 필요 없다"는 주장을 근거 3개로 방어하고, 반대로 필요한 시점의 신호도 제시

---

## Phase 5 — 스토리지 (1주)

**목표**: CSI 파이프라인을 이해하고, 상태ful 워크로드의 배치 결정을 내릴 수 있다.

**핵심 주제**
- PV/PVC 바인딩, StorageClass와 dynamic provisioning, `volumeBindingMode: WaitForFirstConsumer`의 존재 이유
- CSI 아키텍처: controller plugin(provision/attach) vs node plugin(mount), 사이드카들(external-provisioner 등)
- Access mode의 실제 의미(RWO는 "노드" 단위), RWX가 필요한 순간과 수단(NFS/CephFS/EFS)
- Volume expansion, snapshot/clone, ephemeral volume(generic ephemeral, emptyDir)
- StatefulSet + PVC: 노드 장애 시 재attach 흐름과 지연의 원인(attach/detach controller의 타임아웃)
- 데이터베이스 운영: operator 생태계(CloudNativePG, Vitess, Strimzi)

**랩** (`phase-05-storage/`)
1. kind + local-path provisioner로 WaitForFirstConsumer 유무에 따른 스케줄링 차이 재현
2. CSI 드라이버(예: openebs/local) 설치 후 provision → attach → mount 각 단계를 이벤트/로그로 추적
3. 관찰: RWO PVC를 쓰는 Pod의 노드를 내렸을 때 Pod가 다시 뜨기까지의 시간과 원인(멀티 attach 방지)
4. CloudNativePG로 PostgreSQL 클러스터 배포, 페일오버 유발 후 데이터 정합성 확인

**⚖️ 트레이드오프 & 대안**
- **local PV**: 최고 IOPS·지연 / 노드에 데이터 고정 → 노드 장애 = 데이터 접근 불가, 스케줄링 제약. **네트워크 스토리지(EBS류)**: 유연한 재attach / 지연·비용. **분산 스토리지(Ceph/Longhorn)**: 복제·유연성 / 운영 난도 최상급
- **DB on k8s vs 매니지드 DB**: 운영 자동화·비용 절감·이식성 vs 운영 역량 요구·장애 책임. 판단 기준: operator 성숙도, 팀의 스토리지 전문성, 백업·DR 검증 능력. "잘 모르겠으면 매니지드"가 보수적 정답, 단 멀티클라우드·비용 압박·특수 요구는 반례
- **백업 전략**: 스토리지 스냅샷(빠름, 앱 비인지) vs 논리 백업(pg_dump류, 복원 유연) vs operator 내장(WAL 아카이빙) — RPO/RTO로 결정

**완료 기준**
- PVC 생성부터 컨테이너 마운트까지 CSI 컴포넌트별 단계를 설명
- WaitForFirstConsumer가 없으면 생기는 문제를 멀티 AZ 시나리오로 설명
- "우리 서비스 DB를 k8s로 옮기자"는 제안에 대한 찬반 논거를 각 3개씩 제시

---

## Phase 6 — 구성·시크릿·패키징 (1주)

**목표**: 환경별 구성과 민감 정보를 안전하게 관리하고, 매니페스트 패키징 전략을 선택한다.

**핵심 주제**
- ConfigMap/Secret 주입: env vs volume — **업데이트 전파의 결정적 차이**(env는 재시작 필요), immutable 옵션(대규모에서 watch 부하 절감)
- Secret의 실체: base64는 인코딩일 뿐. 보호 계층 분리 — etcd 암호화(at rest, KMS provider) / RBAC(접근 통제) / 노드 레벨(tmpfs)
- 외부 비밀 저장소 연동 패턴과 회전(rotation)
- **Helm**: 템플릿, values 설계, 의존성, hooks, 차트 작성 심화 / **Kustomize**: base/overlay, patch 전략
  - ⚠️ 튜토리얼 단골이던 Bitnami 공개 차트·이미지 카탈로그가 2025년 대폭 축소됨 — 차트 출처·이미지 미러 전략도 학습 대상
- server-side apply와 field ownership (Phase 11에서 심화)

**랩** (`phase-06-config/`)
1. ConfigMap을 env/volume 두 방식으로 주입하고 수정 → 전파 차이 확인, Reloader류로 자동 재시작 구성
2. etcd를 직접 열어 Secret이 평문 저장임을 확인 → encryption at rest 설정 후 재확인
3. External Secrets Operator + (로컬) Vault로 비밀 동기화·회전 구성
4. 같은 앱을 Helm 차트와 Kustomize overlay로 각각 패키징해 dev/prod 분기 — 비교 소감을 NOTES에 기록

**⚖️ 트레이드오프 & 대안**
- **비밀 관리 4종**: Sealed Secrets(git에 암호문 저장, 단순 / 키 관리·회전 부담, 클러스터 종속) vs External Secrets Operator(외부 저장소가 진실의 원천, 회전 용이 / 외부 의존성 추가) vs Vault Agent/CSI(최강 기능·동적 비밀 / 운영 난도) vs SOPS+Flux(git 중심, 가벼움 / 복호화 키 배포 문제). 판단축: "진실의 원천을 git에 둘 것인가, 외부 저장소에 둘 것인가"
- **Helm vs Kustomize**: 템플릿의 표현력·패키지 배포·버전/롤백 vs 템플릿 없는 단순성·가독성. 실무 표준 패턴: **서드파티는 Helm, 자체 앱은 Kustomize**(또는 Helm 렌더 후 Kustomize 후처리). 대안: cdk8s/jsonnet/Timoni — 코드로서의 구성, 단 팀 러닝커브
- **env vs volume 주입**: 편의성 vs 갱신 가능성·노출면(env는 crash dump·child process로 전파되기 쉬움)

**완료 기준**
- "Secret은 안전한가?"에 계층별(저장/전송/접근/노드)로 답할 수 있다
- 비밀 회전이 Pod까지 전파되는 전체 경로를 선택한 도구 기준으로 설명
- Helm 차트의 복잡성이 정당화되는 조건과 Kustomize로 충분한 조건을 구분

---

## Phase 7 — 스케줄링 & 리소스 관리 & 오토스케일링 (1.5주)

**목표**: 리소스 모델의 커널 수준 동작을 이해하고, 스케일링 스택을 설계한다.

**핵심 주제**
- requests/limits의 실체: requests=스케줄링+cgroup 가중치, CPU limit=CFS quota **throttling**, memory limit=OOM kill. QoS 클래스와 eviction 순서
- **CPU limit 논쟁**: "limit을 걸지 마라" 진영(throttling 레이턴시) vs "걸어라" 진영(noisy neighbor, 예측 가능성) — 양쪽 논거와 측정 방법
- 스케줄러 내부: filter → score 플러그인 파이프라인, 스케줄링 프레임워크
- 배치 제어: nodeAffinity/podAffinity/antiAffinity(비용 주의), taint/toleration, topology spread constraints, PDB, priority/preemption
- 수평: **HPA**(메트릭 소스, behavior 튜닝, 플래핑 방지) / 수직: **VPA**, in-place pod resize(1.33+ 기본 활성) / 이벤트 기반: **KEDA**
- 노드: Cluster Autoscaler vs **Karpenter**(bin-packing, consolidation), descheduler

**랩** (`phase-07-scheduling/`)
1. CPU limit을 빡빡하게 걸고 부하 테스트 → `container_cpu_cfs_throttled_periods_total`로 throttling을 측정, limit 제거 후 비교
2. memory limit 초과 → OOMKilled 이벤트와 exit code 137 확인, QoS별 eviction 순서 실험
3. topology spread + PDB + 노드 drain을 조합해 "무중단 노드 교체" 시나리오 완주
4. HPA behavior(scaleUp/scaleDown 정책)를 튜닝해 스파이크 트래픽에서 플래핑 없이 대응
5. KEDA로 큐 길이 기반 스케일링(0까지 축소 포함)

**⚖️ 트레이드오프 & 대안**
- **CPU limit**: 제거 시 p99 개선·활용도 상승 / noisy neighbor 리스크(단, requests가 cgroup 가중치로 최소한 보장). 중간안: 중요 워크로드만 limit 제거, 또는 static CPU manager로 코어 고정
- **HPA vs VPA**: 동시 사용 시 충돌(같은 메트릭 기준). VPA의 재시작 비용은 in-place resize로 완화 중 — 리소스 "추천값" 소스로만 쓰는 보수적 운영도 유효
- **Cluster Autoscaler**(노드그룹 단위, 성숙, 클라우드 중립) vs **Karpenter**(인스턴스 직접 선택·통합 bin-packing·consolidation 공격적 / AWS 중심, Azure 프로바이더 존재, GKE는 NAP이 대응). consolidation의 공격성 vs PDB·안정성
- **preemption**: 중요 워크로드 보장 / 저순위 워크로드의 예측 불가능한 중단 — 배치/서빙 혼합 클러스터 설계 문제

**완료 기준**
- "CPU는 compressible, memory는 incompressible"이 limit 동작 차이로 어떻게 이어지는지 설명
- HPA가 메트릭 수집부터 replica 변경까지 도는 루프와 지연 요소를 설명
- Karpenter consolidation이 PDB·topology spread와 상호작용하며 생길 수 있는 문제 시나리오 제시

---

## Phase 8 — 보안 & 하드닝 (1.5주)

**목표**: 공격 표면을 계층별로 이해하고 각 계층을 **방어·하드닝·탐지**하는 통제를 설계·구현한다. (CKS 범위 + α) — 이 Phase는 전적으로 방어 관점이며, 모든 랩은 하드닝 정책을 적용하고 그 효과를 검증하는 데 초점을 둔다.

**핵심 주제**
- 인증: X.509, ServiceAccount token(projected, 만료·audience 바인딩), OIDC 연동, structured authentication config
- 인가(최소 권한): RBAC 설계 패턴, aggregated ClusterRole, `escalate`/`bind`/`impersonate`처럼 권한 상승을 유발하는 verb를 왜 제한해야 하는지, `kubectl auth can-i`로 권한 범위 점검
- Admission 통제: **Pod Security Admission**(privileged/baseline/restricted) — PSP의 후계. **ValidatingAdmissionPolicy**(CEL, in-tree, 1.30 GA)
- securityContext 하드닝: runAsNonRoot, readOnlyRootFilesystem, capabilities drop, seccompProfile — "restricted" 프로파일을 통과하도록 앱을 다듬기
- 공급망 보안: 이미지 스캔(trivy), 서명·검증(cosign + 정책 엔진), SBOM, 최소 base 이미지 전략(distroless/chainguard류)
- 런타임 탐지: Falco / Tetragon(eBPF)로 이상 행위를 "탐지"하는 관점 — 어떤 시스템콜·파일 접근을 경보로 삼을지
- etcd 암호화, audit logging 정책 설계, 네트워크 격리(Phase 4 연계)

**랩** (`phase-08-security/`) — 모두 하드닝·검증 중심
1. 네임스페이스에 restricted PSA를 적용하고, 하드닝 요구(비root·capability drop·read-only FS)를 충족하도록 샘플 앱의 securityContext를 교정 → 거부되던 Pod가 통과하도록 만들기
2. 역할별 최소 권한 RBAC를 설계하고 `kubectl auth can-i --list`로 과잉 권한이 없는지 감사. 감사 후 불필요한 ClusterRoleBinding 제거
3. ValidatingAdmissionPolicy(CEL)로 조직 규칙(예: 승인된 레지스트리 이미지만 허용, latest 태그 금지)을 코드화하고 위반 리소스가 막히는지 검증
4. 이미지 스캔+서명 검증 파이프라인: trivy로 취약점 게이트, cosign 서명 후 정책 엔진으로 미서명 이미지 배포 차단
5. etcd encryption at rest와 audit policy를 켜고, 민감 리소스 접근이 감사 로그에 남는지 확인
6. Falco/Tetragon 기본 룰셋을 배포하고, 정상 트래픽에서의 노이즈를 줄이도록 룰을 튜닝(탐지 운영 감각)

**⚖️ 트레이드오프 & 대안**
- **정책 엔진 3종**: **PSA**(내장·간단·네임스페이스 라벨 / 3단계 고정, 커스터마이즈 불가) vs **Kyverno**(k8s 친화 YAML 정책·mutate/generate 가능 / 별도 컨트롤러 운영) vs **OPA/Gatekeeper**(Rego의 표현력·범용 / Rego 러닝커브). 단순 하드닝은 PSA+VAP로 충분, 조직 정책이 복잡하면 Kyverno가 실무 기본값
- **런타임 격리 수준**: 일반 컨테이너(공유 커널, 최고 효율) vs **gVisor**(user-space 커널, 시스템콜 격리 / 성능·호환성 비용) vs **Kata Containers**(경량 VM, 강한 격리 / 오버헤드). 멀티테넌시·신뢰 못 할 워크로드일수록 오른쪽. 대부분 조직은 securityContext 하드닝 + 네트워크 격리로 충분
- **런타임 탐지 도입**: 이상 행위 가시성·사고 대응 근거 / 비용: 노이즈·튜닝 공수·오버헤드. 대안: 예방 통제(admission·PSA)를 먼저 탄탄히 하고 탐지는 그 위에 — "예방 없이 탐지만"은 안티패턴
- **보안 vs 개발 속도**: 강한 admission 정책은 사고를 막지만 개발자 마찰을 만든다 → audit 모드로 먼저 관찰 후 enforce로 전환하는 단계적 도입이 정석

**완료 기준**
- 클러스터의 공격 표면을 계층(인증/인가/admission/워크로드/노드/네트워크)으로 나누고, 각 계층의 **예방 통제**를 하나씩 매핑
- restricted PSA를 통과하는 securityContext를 빈 상태에서 작성할 수 있다
- "예방(admission) vs 탐지(runtime)"의 역할 분담과 도입 순서를 설명

---

## Phase 9 — 관측성 (1주)

**목표**: 메트릭·로그·트레이스를 설계하고, 증상에서 원인으로 가는 경로를 데이터로 연결한다.

**핵심 주제**
- 세 신호: metrics / logs / traces와 각자의 비용·보존·질의 특성
- 메트릭: Prometheus 아키텍처(pull, TSDB), PromQL, exporter, ServiceMonitor, recording/alerting rule, cardinality 폭발의 위험
- 장기 저장·수평 확장: Thanos vs Mimir vs Cortex, remote write
- 로그: 수집(Fluent Bit/Vector) → 저장(Loki vs Elasticsearch/OpenSearch) → 질의. 구조화 로깅의 가치
- 트레이싱: OpenTelemetry(수집 표준), 샘플링 전략(head vs tail), 컨텍스트 전파
- **OpenTelemetry Collector**를 중심 파이프라인으로: 신호를 한 곳에서 받아 가공·분배
- 대시보드(Grafana), SLO/에러버짓, alert fatigue 줄이기(증상 기반 알림)

**랩** (`phase-09-observability/`)
1. kube-prometheus-stack 설치, 커스텀 앱에 ServiceMonitor 연결, PromQL로 RED 메트릭 대시보드 작성
2. 고cardinality 라벨(예: user_id)을 넣어 메모리 급증을 재현 → 라벨 제거로 회복
3. OTel Collector를 세워 앱 trace를 수집하고, trace와 로그를 상관(correlation)시켜 한 요청을 끝까지 추적
4. SLO(가용성 99.9%)를 정의하고 번레이트 기반 다중창(multi-window) 알림 구성

**⚖️ 트레이드오프 & 대안**
- **self-hosted(Prometheus 스택) vs managed(Datadog/Grafana Cloud/클라우드 네이티브)**: 비용 통제·데이터 소유·커스터마이즈 vs 운영 부담 제거·빠른 시작. 규모가 커질수록 self-hosted의 비용 이점과 운영 부담이 동시에 커진다
- **로그 저장소: Loki vs Elasticsearch**: Loki(라벨 인덱스만, 저비용, Prometheus 친화 / 전문 검색 약함) vs ES/OpenSearch(강력한 전문 검색·분석 / 리소스·운영 비용 큼). "로그로 무엇을 할 것인가"(grep 수준 vs 분석)로 결정
- **트레이스 샘플링**: head 샘플링(단순·저비용 / 희귀 에러 놓침) vs tail 샘플링(에러·느린 요청 보존 / Collector 상태·비용). 전수 수집은 대개 비현실적
- **알림 철학**: 원인 기반(많고 시끄러움) vs 증상/SLO 기반(적고 행동 가능). alert fatigue는 그 자체가 장애 요인

**완료 기준**
- 한 요청의 지연 원인을 metrics→logs→traces 순으로 좁혀가는 경로를 설명
- cardinality 폭발이 Prometheus를 어떻게 죽이는지와 예방책을 설명
- SLO·에러버짓·번레이트 알림의 관계를 설명

---

## Phase 10 — 클러스터 수명주기 & 운영 (1.5주)

**목표**: 클러스터를 만들고, 업그레이드하고, 백업·복구하고, 장애에 대응하는 운영 역량.

**핵심 주제**
- 부트스트랩: kubeadm로 클러스터를 직접 구성(control-plane HA 포함)해 "클러스터가 무엇으로 이루어지는가"를 체득
- 업그레이드: control-plane → node 순서, skew policy(컴포넌트 간 버전 차이 허용 범위), 무중단 노드 교체
- etcd 운영: 백업(snapshot)·복구, defrag, 디스크·지연 모니터링, 멤버 교체
- 인증서 수명주기: 만료가 부르는 전면 장애, 자동 갱신
- 재해 복구: 클러스터 전체 손실 시나리오, GitOps + etcd 백업 조합의 복구 전략
- 멀티클러스터·멀티테넌시: 네임스페이스 vs 가상클러스터(vCluster) vs 물리 분리, 플릿 관리
- 노드 관리: cordon/drain/uncordon, surge 업그레이드, 이미지 GC

**랩** (`phase-10-lifecycle/`)
1. kubeadm로 HA control-plane(3노드) 클러스터를 수동 구성 — 로드밸런서·etcd 쿼럼 포함
2. 한 마이너 버전 업그레이드를 control-plane→node 순으로 수행, 과정 중 워크로드 무중단 확인
3. etcd snapshot을 뜨고, 리소스를 지운 뒤 snapshot에서 복구
4. 인증서 만료를 앞당겨 장애를 재현하고 갱신으로 복구
5. (선택) vCluster로 가상 클러스터를 띄워 테넌트 격리 모델 비교

**⚖️ 트레이드오프 & 대안**
- **managed(EKS/GKE/AKS) vs self-managed(kubeadm/kops/Cluster API)**: control-plane 운영 부담 제거·SLA vs 완전한 통제·비용 최적화·이식성. 대부분 managed가 기본값, self-managed는 규제·온프렘·특수 커널/네트워크 요구일 때. GKE Autopilot처럼 노드까지 관리받는 선택지는 통제를 더 내주는 대신 운영을 더 덜어낸다
- **업그레이드 전략**: in-place(단순 / 롤백 어려움) vs blue-green 클러스터(안전한 롤백·검증 / 2배 비용·트래픽 이전 복잡). 중요도 높은 클러스터일수록 후자
- **멀티테넌시 격리**: 네임스페이스(가벼움 / 약한 격리, 공유 control-plane) vs vCluster(테넌트별 가상 control-plane / 오버헤드) vs 물리 클러스터 분리(강한 격리 / 운영·비용 폭증)
- **Cluster API**: 선언적·멀티클라우드 클러스터 수명주기 / 러닝커브·성숙도 편차

**완료 기준**
- 컴포넌트 버전 skew 규칙을 설명하고, 왜 control-plane을 먼저 올리는지 말할 수 있다
- etcd 백업만으로 복구되는 것과 안 되는 것(PV 데이터 등)을 구분
- "managed를 쓰는데 왜 쿠버네티스 내부를 알아야 하나"에 반례로 답할 수 있다

---

## Phase 11 — 확장: CRD · Operator · API 내부 (1.5주)

**목표**: 쿠버네티스를 플랫폼으로 확장한다. 컨트롤러를 직접 작성하며 reconciliation을 몸으로 이해한다.

**핵심 주제**
- CRD: OpenAPI 스키마, 검증, 버전·conversion webhook, printer column, subresource(status/scale)
- API machinery 심화: server-side apply와 field ownership, finalizer, owner reference·GC, admission webhook(mutating/validating)의 실체
- Operator 패턴: controller-runtime(Go), reconcile 루프 작성, work queue·rate limiting, 멱등성과 에러 처리
- 작성 도구: Kubebuilder / Operator SDK, 그리고 비-Go 경로
- aggregated API server(고급), scheduler/CSI/device plugin 확장점 개괄

**랩** (`phase-11-operators/`)
1. Kubebuilder로 간단한 CRD + 컨트롤러 작성 (예: `Website` CR → Deployment+Service+Gateway 자동 생성)
2. reconcile를 의도적으로 비멱등하게 만들어 문제를 관찰 → 멱등하게 교정, finalizer로 정리 로직 추가
3. validating webhook을 붙여 잘못된 CR을 거부, conversion webhook으로 v1→v2 마이그레이션
4. server-side apply로 여러 컨트롤러가 같은 오브젝트의 다른 필드를 소유하는 상황 실험

**⚖️ 트레이드오프 & 대안**
- **operator를 만들 것인가**: 운영 지식의 코드화·자동화 / 비용: 개발·유지보수·버그가 곧 프로덕션 장애. 먼저 물어라 — Helm/Kustomize + 기존 operator로 충분한가? "operator를 쓴다 ≠ operator를 만든다"
- **작성 프레임워크**: controller-runtime/Kubebuilder(Go 생태계 표준·성숙 / Go 필요) vs Operator SDK(Ansible/Helm 기반 operator로 저코드 / 표현력 제한) vs Metacontroller·kube-rs(Rust)·shell-operator 등 비-Go 경로
- **webhook의 리스크**: 강력한 통제 / 비용: webhook이 죽으면 관련 API 요청이 막혀 **클러스터 전체 장애**로 번질 수 있음 → failurePolicy·timeout·네임스페이스 예외 설계가 필수
- **CRD vs ConfigMap+컨트롤러 vs aggregated API**: 선언적 API의 정식화 vs 단순함 vs 완전한 제어(성능·스토리지 커스터마이즈)

**완료 기준**
- reconcile 루프가 "level-triggered·멱등"이어야 하는 이유를 실패 사례로 설명
- finalizer가 없을 때 생기는 리소스 누수 시나리오를 설명
- admission webhook이 클러스터 가용성에 주는 리스크와 완화 설계를 설명

---

## Phase 12 — GitOps & 배포 파이프라인 (1주)

**목표**: 선언적 배포를 git을 진실의 원천으로 자동화하고, 점진적 배포로 리스크를 통제한다.

**핵심 주제**
- GitOps 원칙: 선언적·버전관리·자동 동기화·지속적 reconciliation(drift 감지·교정)
- **Argo CD**(UI·app-of-apps·sync wave) vs **Flux**(GitOps Toolkit·경량·CRD 중심)
- 환경·클러스터 분기 전략: 디렉토리 vs 브랜치, ApplicationSet/Kustomize overlay, promotion 흐름
- 점진적 배포: **Argo Rollouts**/Flagger로 canary·blue-green을 메트릭 분석 기반 자동 승격/롤백
- 시크릿과 GitOps의 긴장(Phase 6 연계), drift·수동 변경 처리 정책
- 렌더링 파이프라인: git에 평문 매니페스트 vs 런타임 템플릿 렌더(rendered manifests 패턴)

**랩** (`phase-12-gitops/`)
1. Argo CD 설치, app-of-apps로 이 레포의 phase별 앱들을 선언적으로 관리
2. 수동으로 `kubectl edit`해 drift를 만든 뒤 Argo CD가 감지·교정하는 과정 관찰(self-heal on/off 비교)
3. Argo Rollouts로 canary 배포 + Prometheus 메트릭 분석 기반 자동 롤백 구성
4. ApplicationSet로 dev/stg/prod 3환경에 같은 앱을 파라미터만 바꿔 전개

**⚖️ 트레이드오프 & 대안**
- **GitOps(pull) vs CI push(kubectl/helm from pipeline)**: drift 교정·감사성·클러스터 자격증명 비노출 vs 단순함·기존 파이프라인 재사용. push는 "배포했지만 실제 상태는 모른다"가 약점
- **Argo CD vs Flux**: 강력한 UI·멀티테넌시·직관성 vs 경량·조합형·Kubernetes-native. 팀이 UI 기반 가시성을 원하면 Argo, 완전한 CRD/자동화 지향이면 Flux
- **canary 자동화 vs 수동 승격**: 안전·빠른 롤백 vs 파이프라인·메트릭 신뢰도 요구. 메트릭이 부실하면 자동 canary는 오히려 위험
- **브랜치 per 환경 vs 디렉토리 per 환경**: 익숙함 vs promotion 추적 용이성(현재는 디렉토리/overlay가 우세)

**완료 기준**
- "git에 있는 것이 곧 클러스터 상태"가 깨지는 경우(drift, 수동 변경)와 처리 정책을 설명
- canary 자동 롤백이 동작하려면 선행되어야 할 관측성 조건을 설명
- 시크릿을 GitOps에 통합하는 방법과 각 방법의 신뢰 경계를 설명

---

## Phase 13 — 프로덕션 심화 & 캡스톤 (2주)

**목표**: 지금까지의 모든 레이어를 하나의 프로덕션급 플랫폼으로 통합하고, 규모·비용·장애의 현실을 마주한다.

**핵심 주제**
- 규모의 한계: API server·etcd·스케줄러의 스케일 병목, 대규모에서의 known limit, Pod 밀도·IP·conntrack 한계
- 비용 관리: FinOps(OpenCost/Kubecost), bin-packing, spot/preemptible 인스턴스, requests 우측화(rightsizing)
- 신뢰성 엔지니어링: 장애 주입·카오스 테스트, 용량 계획, multi-AZ/multi-region 설계
- 플랫폼 엔지니어링 관점: 내부 개발자 플랫폼(IDP), 골든 패스, Backstage·포털, 셀프서비스의 가드레일
- 트러블슈팅 종합: 증상별 디버깅 플로우차트(Pending / CrashLoop / 네트워크 단절 / 노드 NotReady / 느린 API)

**캡스톤** (`phase-13-capstone/`) — 아래를 하나의 레포로 통합
1. kubeadm 또는 managed 위에 HA 클러스터 + 선택한 CNI(Phase 4)
2. GitOps(Argo CD/Flux)로 전부 선언적 관리, 비밀은 External Secrets
3. 멀티티어 앱(스테이트리스 API + operator로 관리되는 상태ful 저장소) 배포
4. Gateway API L7 라우팅 + 점진적 배포(canary) + default-deny NetworkPolicy
5. 관측성 풀스택(메트릭/로그/트레이스) + SLO 알림
6. 보안 하드닝(restricted PSA + 정책 엔진 + 이미지 서명 검증)
7. 오토스케일링(HPA/KEDA + Karpenter/CA)과 비용 대시보드
8. **런북 작성**: 의도적으로 장애를 주입하고(노드 다운, 인증서 만료, DNS 장애 등) 복구 절차를 문서화

**⚖️ 트레이드오프 & 대안 (종합)**
- **비용 vs 안정성**: spot 인스턴스·공격적 consolidation·낮은 replica는 비용을 줄이지만 가용성을 깎는다. 워크로드 등급별로 다른 정책을 적용하는 것이 현실적 타협
- **플랫폼 추상화 수준**: 개발자에게 raw k8s를 노출(유연·학습비용) vs 추상화된 셀프서비스 플랫폼(생산성·가드레일 / 구축·유지보수 비용, 유연성 상실). 조직 규모가 임계점을 넘을 때 플랫폼팀이 정당화된다
- **멀티클라우드·이식성**: 벤더 종속 회피 vs 최소공통분모로 인한 기능 포기·복잡도. 대부분의 조직에 "진짜" 멀티클라우드는 비용이 효용을 넘는다
- **복잡도 그 자체**: 쿠버네티스를 쓸 것인가? 소규모·단순 워크로드엔 PaaS/서버리스/단일 VM이 더 나을 수 있다 — 이 커리큘럼의 마지막 교훈은 "언제 k8s를 쓰지 않을지"를 아는 것

**완료 기준**
- 캡스톤 플랫폼을 처음 보는 사람에게 15분 안에 아키텍처와 핵심 설계 결정을 트레이드오프와 함께 설명
- 주입한 장애 각각에 대해 "증상 → 진단 경로 → 원인 → 복구 → 재발 방지"를 런북으로 제시
- "이 조직에는 쿠버네티스가 과하다"가 참이 되는 조건을 구체적으로 제시

---

## 부록 A — 학습 자원

- **1차 자료(최우선)**: 공식 문서(kubernetes.io), API 레퍼런스, 관련 KEP(설계 의도·거부된 대안이 담겨 있어 트레이드오프 학습에 최고)
- **깊이**: *Kubernetes in Action*(멘탈 모델), *Programming Kubernetes*(확장/operator), CNCF 프로젝트별 공식 문서
- **운영 감각**: 각 프로젝트의 production best practices, 포스트모템 모음, SIG 미팅 노트·녹화
- **실습 플랫폼**: killercoda/killer.sh(CKA/CKS 시뮬레이터), 로컬 kind가 90%를 대체
- **갱신 추적**: 릴리스 노트와 deprecation 가이드를 매 마이너 버전 확인(이 커리큘럼의 버전 표기는 참고용이며 공식 문서로 재확인)

## 부록 B — 커리큘럼 사용법

1. Phase는 순서대로. 특히 **Phase 1(아키텍처)은 건너뛰지 말 것** — 이후 전부의 멘탈 모델이다.
2. 각 랩 디렉토리에 `NOTES.md`를 두고 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 기록한다. 이 기록이 실력이자 포트폴리오.
3. "완료 기준"의 질문에 소리 내어 답해보고, 막히면 그 Phase를 아직 끝내지 않은 것으로 간주한다.
4. 자격증(CKA/CKAD/CKS)을 원하면 해당 Phase 완료 후 시뮬레이터로 속도 훈련을 얹는다.
5. 버전·생태계는 계속 변한다. 이 문서는 지도이지 영토가 아니다 — 의심되면 항상 공식 문서가 우선.
