# Phase 7 — 스케줄링 & 리소스 관리 & 오토스케일링

> 목표: 리소스 모델의 **커널 수준 동작**(CFS throttling, OOM kill, QoS)을 눈으로 확인하고,
> **스케일링 스택**(HPA behavior, KEDA)과 **무중단 노드 교체**(PDB + topology spread)를 설계·관찰한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 7.

## 사전 준비

Phase 0에서 만든 멀티노드 kind 클러스터(context **`kind-k8s-mastery`**)가 떠 있어야 한다.

```bash
# 없으면 Phase 0에서 생성 (control-plane 1 + worker 3, zone 라벨 포함)
bash phase-00-setup/scripts/01-create-cluster.sh
kubectl --context kind-k8s-mastery get nodes
```

- **lab 1~3**: 추가 설치 불필요 (busybox/nginx 이미지만 사용).
- **lab 4(HPA)**: `metrics-server` 를 스크립트가 설치한다(kind용 `--kubelet-insecure-tls` 패치 포함).
- **lab 5(KEDA, 선택)**: `helm` 필요. 없으면 `brew install helm`.

> ℹ️ 버전 핀: metrics-server `v0.9.0`, KEDA chart `2.21.0` (2026-10 기준 최신).
> 각 설치 스크립트 상단 주석의 릴리스 페이지에서 최신 버전을 재확인하고 환경변수로 덮어쓸 수 있다.
> 예: `METRICS_SERVER_VERSION=v0.9.1 bash .../04-metrics-server-install.sh`

### ⚖️ 이 Phase의 핵심 트레이드오프

| 주제 | 한쪽 | 반대쪽 | 판단축 |
|---|---|---|---|
| **CPU limit** | 제거: p99 개선·활용도↑ | 유지: noisy neighbor 방지·예측성 | requests가 최소몫 보장 → 중요 워크로드만 limit 제거가 중간안 |
| **HPA vs VPA** | HPA: replica 수평 확장 | VPA: Pod 리소스 수직 조정(재시작) | 같은 메트릭이면 충돌. VPA는 추천값/ in-place resize로 완화 |
| **노드 오토스케일** | Cluster Autoscaler: 노드그룹·성숙·중립 | Karpenter: 인스턴스 직접 선택·공격적 consolidation | consolidation 공격성 vs PDB/안정성 (AWS 중심) |
| **preemption** | 중요 워크로드 보장 | 저순위 워크로드의 예측 불가 중단 | 배치/서빙 혼합 클러스터 설계 문제 |

## 실습 순서

```bash
# 1. CPU throttling (CFS quota) — "느려짐"
bash phase-07-scheduling/scripts/01-cpu-throttling.sh

# 2. OOMKilled & QoS — "죽음" + 축출 우선순위
bash phase-07-scheduling/scripts/02-oom-and-qos.sh

# 3. 무중단 노드 교체 — topology spread + PDB + drain
bash phase-07-scheduling/scripts/03-node-drain-pdb.sh

# 4. HPA behavior — 플래핑 방지 튜닝
bash phase-07-scheduling/scripts/04-metrics-server-install.sh   # (사전) metrics-server
bash phase-07-scheduling/scripts/04-hpa-behavior.sh

# 5. (선택) KEDA — 이벤트/스케줄 기반, 0까지 축소
bash phase-07-scheduling/scripts/05-keda-install.sh             # (사전) helm으로 KEDA
bash phase-07-scheduling/scripts/05-keda-scaledobject.sh

# (끝나면) 랩 리소스 정리
bash phase-07-scheduling/scripts/99-cleanup.sh
```

관찰 시간을 조절하려면 환경변수로 덮어쓴다. 예:

```bash
WARMUP=30 bash phase-07-scheduling/scripts/01-cpu-throttling.sh
UP_SECONDS=180 HOLD_SECONDS=120 bash phase-07-scheduling/scripts/04-hpa-behavior.sh
OBSERVE_SECONDS=600 bash phase-07-scheduling/scripts/05-keda-scaledobject.sh
```

## 각 랩이 가르치는 것

- **lab 1 — CPU throttling**: CPU는 *compressible*. limit 초과 시 커널 CFS가 quota 소진으로
  프로세스를 멈춘다(throttling) — 죽이지 않고 "느리게". `/sys/fs/cgroup/cpu.stat`(cgroup v2)의
  `nr_throttled`/`throttled_usec` 로 직접 측정하고, limit 상향본과 비교한다. → "CPU limit 논쟁"의 근거.
- **lab 2 — OOMKilled & QoS**: memory는 *incompressible*. limit 초과 = SIGKILL(OOMKilled, exit 137).
  `describe` 이벤트로 확인하고, Guaranteed/Burstable/BestEffort 세 Pod의 `status.qosClass` 와
  축출 우선순위(BestEffort 먼저)를 연결한다.
- **lab 3 — 무중단 노드 교체**: `topologySpreadConstraints`(soft)로 노드/zone에 고루 퍼뜨린 Deployment에
  `PodDisruptionBudget`(maxUnavailable 1)을 걸고 `kubectl drain`. PDB가 Eviction을 직렬화(429로 거부·재시도)해
  동시 축출을 막는 것을 관찰 → 무중단 유지. hard spread였다면 왜 교착되는지도 설명.
- **lab 4 — HPA behavior**: metrics-server→HPA 제어 루프를 돌려보고, `behavior`로 scaleUp은 즉시(window 0),
  scaleDown은 관성(window 300s)을 주어 **플래핑을 억제**한다. `autoscaling/v2` 사용.
- **lab 5 — KEDA(선택)**: cron 트리거 `ScaledObject`로 **0까지 축소**. HPA가 못 하는 0 스케일과
  이벤트 기반 확장의 동작 모델(0↔1은 KEDA, 1↔N은 내부 HPA)을 관찰.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. **"CPU는 compressible, memory는 incompressible"** 이 limit 동작 차이(throttling vs OOMKill)로
   어떻게 이어지는지 설명할 수 있다.
2. **HPA가 메트릭 수집부터 replica 변경까지 도는 루프**와 지연 요소(수집 주기, sync period,
   안정화 윈도우)를 설명할 수 있다.
3. **QoS 3종과 eviction 우선순위**의 관계, 그리고 "선언이 곧 보호"인 이유를 설명할 수 있다.
4. **PDB가 막는 중단과 막지 못하는 중단**(자발적 vs 비자발적)을 구분하고, drain이 무중단이 되는
   메커니즘(Eviction API + 429)을 설명할 수 있다.
5. (보너스) **Karpenter consolidation** 이 PDB·topology spread와 상호작용하며 생길 수 있는
   문제 시나리오를 제시할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.

## 디렉토리

```
phase-07-scheduling/
├── README.md
├── NOTES.md
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 01-cpu-throttled.yaml      # CPU limit 100m busy-loop
│   ├── 01-cpu-relaxed.yaml        # 비교군: limit 1000m
│   ├── 02-oom.yaml                # memory limit 초과 → OOMKilled
│   ├── 02-qos.yaml                # Guaranteed / Burstable / BestEffort
│   ├── 03-web.yaml                # topology spread Deployment + Service
│   ├── 03-pdb.yaml                # PodDisruptionBudget
│   ├── 04-php-apache.yaml         # HPA 대상 앱
│   ├── 04-hpa.yaml                # HPA v2 + behavior
│   └── 05-scaledobject.yaml       # KEDA cron ScaledObject
└── scripts/
    ├── 01-cpu-throttling.sh
    ├── 02-oom-and-qos.sh
    ├── 03-node-drain-pdb.sh
    ├── 04-metrics-server-install.sh
    ├── 04-hpa-behavior.sh
    ├── 05-keda-install.sh
    ├── 05-keda-scaledobject.sh
    └── 99-cleanup.sh
```
