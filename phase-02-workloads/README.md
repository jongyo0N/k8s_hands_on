# Phase 2 — 워크로드 & Pod 심화

> 목표: 워크로드 컨트롤러를 상황에 맞게 선택하고, 무중단 배포·우아한 종료를 실제로 보장한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 2.

## 전제

- Phase 0의 kind 클러스터가 떠 있어야 한다 (context `kind-k8s-mastery`, worker 3노드).
  - 없다면: `bash phase-00-setup/scripts/01-create-cluster.sh`
- 모든 랩은 네임스페이스 `phase-02`에서 돈다. 매니페스트에 네임스페이스가 박혀 있고, 각 스크립트는 시작 시 네임스페이스를 보장한다.
- 추가 도구 설치 불필요 — `kubectl`만 있으면 된다. 부하 생성기는 `curlimages/curl` 이미지를 클러스터 안에서 띄운다.

### 이 Phase에서 쓰는 이미지

| 이미지 | 용도 |
|---|---|
| `busybox:1.36` | 느리게 뜨는 앱(httpd) 흉내 / Job worker |
| `nginx:1.27-alpine` | rolling update 대상 웹 서버 |
| `redis:7-alpine` | StatefulSet 3-replica |
| `curlimages/curl:8.11.1` | 무중단 검증용 부하 생성기 |

## 실습 순서

```bash
bash phase-02-workloads/scripts/00-namespace.sh            # 공용 네임스페이스 phase-02 생성
bash phase-02-workloads/scripts/01-startup-probe.sh        # lab1: startup probe 없는 CrashLoop → 수정
bash phase-02-workloads/scripts/02-rolling-update.sh       # lab2: 부하 중 무중단 rolling update (5xx 0)
bash phase-02-workloads/scripts/03-statefulset.sh          # lab3: StatefulSet identity (강제 삭제 후 유지)
bash phase-02-workloads/scripts/04-job-podfailurepolicy.sh # lab4: Job podFailurePolicy (재시도 vs 포기)
bash phase-02-workloads/scripts/99-cleanup.sh              # (끝나면) 네임스페이스 삭제
```

각 랩은 ①정상/결함 구성을 **만들고** ②증상을 **관찰하고** ③원인을 **설명**하는 순서다. 스크립트 맨 끝의 "해석" 블록이 ③에 해당한다.

## 각 랩이 가르치는 것

- **lab 1 — probe 3종의 분업** (`01-startup-probe.sh`)
  기동에 20초 걸리는 앱에 startup probe 없이 liveness만 걸면, liveness가 기동 전에 때려 재시작 폭풍(CrashLoopBackOff)이 난다. startup probe를 붙여 "기동 구간"을 liveness와 분리하면 해소된다. before/after 매니페스트로 대조.
  → liveness는 "복구 불가 상태 치유"용, startup은 "느린 기동 유예"용. 목적이 다르다.

- **lab 2 — 무중단 rolling update** (`02-rolling-update.sh`)
  readinessProbe + preStop(sleep) + `terminationGracePeriodSeconds` + `maxSurge/maxUnavailable` 조합으로, 부하가 흐르는 중 rollout을 돌려도 실패 요청 0을 만든다. 클러스터 안에서 curl 루프로 5xx/커넥션 거부를 집계.
  → 종료 중에도 트래픽이 오는 **엔드포인트 전파 지연 레이스**와 그 해법을 체감.

- **lab 3 — StatefulSet identity** (`03-statefulset.sh`)
  redis 3-replica StatefulSet + headless Service. `redis-0`을 강제 삭제(`--force --grace-period=0`)해도, 같은 이름·같은 PVC(`data-redis-0`)로 재생성되어 데이터가 유지되는 것을 UID 비교로 관찰.
  → StatefulSet이 보장하는 것(이름·네트워크·스토리지 identity)과 보장하지 않는 것(복제·리더 선출)의 경계.

- **lab 4 — Job podFailurePolicy** (`04-job-podfailurepolicy.sh`)
  동일한 `podFailurePolicy`를 가진 두 Job이 컨테이너 exit code만으로 갈린다: exit 42는 `FailJob`으로 즉시 포기(재시도 0), exit 1은 규칙 미해당이라 `backoffLimit`까지 재시도.
  → "재시도할 실패 vs 즉시 포기할 실패"를 선언적으로 구분. 인프라 교란(`DisruptionTarget`)은 `Ignore`로 공짜 재시도.

## ⚖️ 트레이드오프 (요약, 자세히는 CURRICULUM.md)

- **liveness probe**: 데드락 자동 복구 ↔ 일시 과부하를 재시작 폭풍으로 증폭. 보수적 운영은 liveness를 빼고 readiness만. 외부 의존성은 절대 liveness에 넣지 않는다.
- **배포 전략**: rolling(기본·리소스 효율) vs recreate(단순·다운타임) vs blue-green(즉시 롤백·2배 자원) vs canary(리스크 최소·파이프라인 복잡). canary는 Phase 12.
- **StatefulSet vs Deployment+PVC vs Operator**: 안정적 identity만 필요하면 StatefulSet, 복제·failover까지 필요하면 operator.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. readiness와 liveness가 각각 실패했을 때 일어나는 일의 차이를 컴포넌트 수준(kubelet / 엔드포인트 / kube-proxy)으로 설명할 수 있다.
2. SIGTERM 이후에도 요청이 들어오는 이유(엔드포인트 전파의 비동기성)와 완화책 3가지를 말할 수 있다.
3. StatefulSet이 보장하는 것(안정적 identity)과 보장하지 않는 것(데이터 복제, 리더 선출)을 구분할 수 있다.
4. (보너스) Job에서 "즉시 포기할 실패"와 "재시도할 실패"를 podFailurePolicy로 어떻게 나누는지 설명할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.
