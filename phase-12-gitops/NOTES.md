# Phase 12 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] Argo CD 설치 (`01`) — 버전: ______ / admin 비번 확보: ______
- [ ] app-of-apps 부트스트랩 (`01b`) — 루트 repoURL: ______ / targetRevision: ______
- [ ] drift & self-heal 관찰 (`02`)
- [ ] Argo Rollouts 설치 + canary 트리거 (`03`, `03b`) — 버전: ______
- [ ] ApplicationSet 전개 (`04`) — generator: list / git (택1): ______

## 2. 관찰한 증상 (사실만)

### lab 1 — app-of-apps 트리
```
kubectl -n argocd get applications 결과:
  root           sync=______  health=______
  phase-12-web   sync=______  health=______
phase-12 네임스페이스 워크로드(web) pods 수: ______
```

### lab 2 — drift & self-heal
| 단계 | sync | health | replicas(live) |
|---|---|---|---|
| 초기(git=선언값) | Synced | Healthy | 2 |
| selfHeal OFF + 수동 scale 5 | ______ | ______ | ______ |
| selfHeal ON (잠시 후) | ______ | ______ | ______ |

- OutOfSync는 떴지만 replicas가 안 돌아온 구간이 있었나? (selfHeal OFF): ______
- selfHeal ON 후 교정까지 대략 걸린 시간: ______ 초

### lab 3 — canary
- 이미지 변경 전/후: ______ → ______
- `setWeight: 20` 시점 새 버전 pod 비율(대략): ______
- `pause: {}`에서 멈췄나? 수동 `promote`로 넘어갔나: ______
- analysis 단계 결과: Passed / Error / Inconclusive (택1): ______
  - (Prometheus 미설치라면 결과가 ______ 였고, Rollout은 ______ 되었다)

### lab 4 — ApplicationSet
```
생성된 Application: web-dev / web-stg / web-prod
환경별 replicas  : dev=____  stg=____  prod=____   (기대: 1/2/3)
```

## 3. 원인 가설과 검증

- selfHeal OFF인데도 Argo가 OutOfSync를 "표시"는 한 이유(내 설명):
  > ______ (힌트: 감지=지속적 reconcile, 교정=selfHeal 스위치. 둘은 별개다.)

- Prometheus가 없을 때 canary가 자동 롤백(또는 멈춤)된 이유(내 설명):
  > ______ (힌트: AnalysisRun이 메트릭을 못 받으면 Error/Inconclusive → abort)

- ApplicationSet이 환경 간 "파라미터만" 바꿀 수 있던 메커니즘(내 설명):
  > ______ (힌트: generator가 만든 파라미터를 하나의 template에 치환)

## 4. 배운 트레이드오프
- GitOps(pull) vs CI push — 내 상황에선 ______ 가 적합. 이유: ______
- Argo CD vs Flux — ______ 선택. 이유: ______
- canary 자동 승격 vs 수동 승격 — 메트릭 신뢰도가 ______ 할 때만 자동이 안전.
- 브랜치 per 환경 vs 디렉토리 per 환경 — 내 선택: ______ (promotion 추적 관점)

## 5. 완료 기준 — 질문에 답하기

**Q1. "git=클러스터 상태"가 깨지는 경우와 Argo CD의 처리 정책을 설명하라.**
- 깨지는 경우(drift): ______ (예: 수동 kubectl, HPA, 핫픽스)
- 감지 vs 교정: ______
- `prune` 의미: ______ / `selfHeal` 의미: ______
- selfHeal을 일부러 끄는 상황: ______

**Q2. canary 자동 롤백의 선행 관측성 조건은?**
> ______
> (키워드: 신뢰할 수 있는 메트릭, successCondition, failureLimit, 가짜 통과/가짜 실패)

**Q3. 시크릿을 GitOps에 통합하는 방법과 각 신뢰 경계는?**
1. Sealed Secrets: ______ (암호문만 git, 복호화는 클러스터 내 컨트롤러 키)
2. SOPS(+age/KMS): ______ (복호화 키의 신뢰 경계는? )
3. External Secrets Operator: ______ (진실의 원천은 외부 비밀 저장소)
- 공통 원칙: ______ (평문을 git에 두지 않는다 / 신뢰 경계 = 복호화 키를 쥔 주체)

**Q4. (보너스) GitOps/Argo CD 선택을 한 문장으로 방어하라.**
> GitOps(pull) 대신/대비: ______
> Argo CD 대신/대비 Flux: ______

---
_다음 Phase로 넘어가기 전에 Q1~Q3을 막힘없이 답할 수 있는지 확인._
