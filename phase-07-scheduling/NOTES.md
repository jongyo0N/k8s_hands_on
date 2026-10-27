# Phase 7 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] CPU throttling 측정·비교 (`01`) — throttled(limit 100m) vs relaxed(limit 1000m)
- [ ] OOMKilled & QoS (`02`) — exit 137 확인, QoS 3종 분류
- [ ] 무중단 노드 교체 (`03`) — drain 중 PDB가 동시 축출 차단
- [ ] HPA behavior (`04`) — metrics-server 설치 + scaleUp/scaleDown 튜닝
- [ ] (선택) KEDA (`05`) — cron 트리거로 0까지 축소

## 2. 관찰한 증상 (사실만)

### lab 1 — CPU throttling (cpu.stat)
```
# cpu-throttled (limit 100m)
nr_periods     = ______
nr_throttled   = ______      # periods에 근접할수록 "거의 매번 멈춤"
throttled_usec = ______      # (cgroup v1이면 throttled_time, 나노초)
throttle 비율   = ______ %

# cpu-relaxed (limit 1000m)
nr_throttled   = ______      # 0에 수렴?
throttle 비율   = ______ %
```
`kubectl top pod -l app=cpu-demo` 실제 사용량: throttled=______m, relaxed=______m

### lab 2 — OOMKilled & QoS
```
oom-victim:
  lastState.terminated.reason = ______   # 기대: OOMKilled
  exitCode                    = ______   # 기대: 137 (=128+9, SIGKILL)
  restartCount                = ______
describe 이벤트에서 본 문구  = ______    # 예: "Back-off restarting failed container"

qosClass:
  qos-guaranteed  = ______   # 기대: Guaranteed
  qos-burstable   = ______   # 기대: Burstable
  qos-besteffort  = ______   # 기대: BestEffort
```

### lab 3 — 노드 drain + PDB
- 교체 대상 노드: ______ (web Pod ___개 보유)
- PDB `ALLOWED DISRUPTIONS` 값: ______
- drain 로그에서 "would violate ... disruption budget"(429)를 봤는가? ______
- drain 내내 `availableReplicas` 최저값: ______ (4개 중 최소 ___개 유지)
- hard spread(DoNotSchedule)였다면 어떻게 달랐을까(가설): ______

### lab 4 — HPA behavior
- 부하 투입 후 CPU% 최고치: ______ %, 그때 desiredReplicas: ______
- scale-up 이 체감상 걸린 시간: 약 ______ 초 (window=0)
- 부하 제거 후 `HOLD_SECONDS` 동안 replica가 줄었는가? ______ (기대: 안 줄어듦 — window 300s)

### lab 5 — KEDA (선택)
- 패치된 cron 창: start=`______`  end=`______` (UTC)
- 전이 관찰: 시작 replicas ___ → (창 전) ___ → (창 안) ___ → (창 후) ___
- `ScaledObject.Active` 가 True 로 바뀐 시점의 replicas: ______

## 3. 원인 가설과 검증

- throttled Pod가 "죽지 않고 느려진" 이유(내 설명):
  > ______ (키워드: CFS quota, period, compressible)

- oom-victim이 SIGTERM 유예 없이 즉사(137)한 이유(내 설명):
  > ______ (키워드: incompressible, 커널 OOM killer, SIGKILL)

- drain이 무중단이었던 이유(내 설명):
  > ______ (키워드: Eviction API, PDB 429, 직렬화)

## 4. 배운 트레이드오프
- CPU limit: 제거의 이득 ______ / 비용 ______ / 내 결론 ______
- HPA vs VPA: 충돌 지점 ______ / 완화책 ______
- Cluster Autoscaler vs Karpenter: 내 상황엔 ______ 가 적합. 이유: ______

## 5. 완료 기준 — 질문에 답하기

**Q1. "CPU는 compressible, memory는 incompressible"이 limit 동작 차이로 어떻게 이어지나?**
> CPU limit 초과 → ______
> memory limit 초과 → ______

**Q2. HPA가 메트릭 수집부터 replica 변경까지 도는 루프와 지연 요소는?**
> 루프: metrics-server(kubelet/cAdvisor) → ______ → desiredReplicas 계산 → 스케일
> 지연 요소: ______ , ______ , ______ (수집 주기 / sync period / 안정화 윈도우)

**Q3. QoS 3종과 eviction 우선순위, "선언이 곧 보호"의 의미는?**
> 축출 순서: ______ → ______ → ______
> 이유: ______

**Q4. PDB가 막는 중단 vs 막지 못하는 중단, drain이 무중단이 되는 메커니즘은?**
> 막음(자발적): ______ / 못 막음(비자발적): ______
> 메커니즘: ______

**Q5. (보너스) Karpenter consolidation이 PDB·topology spread와 충돌하는 시나리오는?**
> ______

---
_다음 Phase로 넘어가기 전에 Q1~Q5를 막힘없이 답할 수 있는지 확인._
