# Phase 2 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] 네임스페이스 생성 (`00`)
- [ ] lab1 CrashLoop 재현 → startup probe로 수정 (`01`)
- [ ] lab2 무중단 rolling update, 실패 요청 0 (`02`)
- [ ] lab3 StatefulSet identity 유지 관찰 (`03`)
- [ ] lab4 Job podFailurePolicy 분기 확인 (`04`)

## 2. 관찰한 증상 (사실만)

### lab 1 — startup probe
- BEFORE(`slow-start-broken`) 최종 STATUS: ______  / RESTARTS: ______
- describe Events에서 본 종료 사유 문구: ______ (예: `Liveness probe failed ... Killing`)
- AFTER(`slow-start-fixed`)가 Ready까지 걸린 대략 시간: ______ 초 / RESTARTS: ______

### lab 2 — 무중단 rolling update
- 부하 생성기 로그의 BAD(실패) 줄 수: ______  (목표 0)
- 실패가 있었다면 code 값: ______ (000=커넥션 거부, 5xx=서버 오류)
- rollout 동안 Ready Pod 수가 4 밑으로 내려갔는가? ______ (maxUnavailable=0 효과)

### lab 3 — StatefulSet identity
```
redis-0 UID (삭제 전) = ______
redis-0 UID (삭제 후) = ______    # 다름? 같음?
redis-0 PVC (삭제 전) = ______
redis-0 PVC (삭제 후) = ______    # 같아야 identity 유지
canary 값 (삭제 후)   = ______    # 데이터 생존?
```

### lab 4 — Job podFailurePolicy
- CASE A (exit 42) 생성된 Pod 수: ______  / Job reason: ______
- CASE B (exit 1)  생성된 Pod 수: ______  / Job reason: ______

## 3. 원인 가설과 검증

- lab1: liveness만으로 CrashLoop이 난 메커니즘(내 설명):
  > ______ (키워드: initialDelay/period/failureThreshold, 기동 20초, 재시작 백오프)

- lab2: preStop sleep을 빼면 왜 롤아웃 중 요청이 실패할 수 있는가(내 설명):
  > ______ (키워드: Terminating, EndpointSlice 제거 전파, kube-proxy, 비동기 레이스)

- lab3: Pod를 강제로 지웠는데 데이터가 남은 이유(내 설명):
  > ______ (키워드: volumeClaimTemplates, ordinal-PVC 고정 바인딩, AOF)

- lab4: 같은 정책인데 exit 42와 exit 1의 운명이 갈린 이유(내 설명):
  > ______ (키워드: onExitCodes, FailJob vs 기본 Count, backoffLimit)

## 4. 배운 트레이드오프
- probe 공격성: liveness를 공격적으로 걸 때의 이득 ______ / 비용 ______
- 배포 전략: 내 서비스엔 ______ 가 적합. 이유: ______
- StatefulSet vs operator: ______ 가 필요해지는 순간은 ______

## 5. 완료 기준 — 질문에 답하기

**Q1. readiness와 liveness가 각각 실패하면 무슨 일이 일어나는가? (컴포넌트 수준)**
- readiness 실패 → ______ (힌트: 엔드포인트에서 제거, 컨테이너는 재시작 안 함)
- liveness 실패  → ______ (힌트: kubelet이 컨테이너 재시작)
- startup 실패   → ______ (힌트: failureThreshold 초과 시 재시작, 그 전엔 다른 probe 비활성)

**Q2. SIGTERM 이후에도 요청이 들어오는 이유와 완화책 3가지는?**
> 이유: ______ (엔드포인트 전파의 비동기성 — Pod는 Terminating인데 kube-proxy 규칙엔 아직 남음)
> 완화책 1: ______ (preStop sleep로 종료 지연 → 전파 시간 확보)
> 완화책 2: ______ (readinessProbe로 준비된 Pod만 등록)
> 완화책 3: ______ (terminationGracePeriodSeconds 충분히, 앱이 SIGTERM에 graceful drain)

**Q3. StatefulSet이 보장하는 것과 보장하지 않는 것은?**
> 보장: ______ (이름·네트워크·스토리지 identity, 순서)
> 비보장: ______ (데이터 복제, 리더 선출, failover)

**Q4. (보너스) Job에서 "즉시 포기할 실패"와 "재시도할 실패"를 어떻게 나누나?**
> ______ (podFailurePolicy: onExitCodes→FailJob으로 영구 오류 즉시 중단, 나머지는 Count로 backoffLimit까지, DisruptionTarget은 Ignore)

---
_다음 Phase로 넘어가기 전에 Q1~Q4를 막힘없이 답할 수 있는지 확인._
