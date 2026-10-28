# Phase 1 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] API 요청 직접 관찰 (`01`) — `--raw`, `-v=9`, apiserver 매니페스트, `kubectl proxy`
- [ ] etcd 저장 바이트 열람 (`02`) — `etcdctl get /registry/... --print-value-only`
- [ ] scheduler 정지 관찰 (`03`) — nodeName 없는 Pod vs 박은 Pod
- [ ] reconciliation/자가치유 관찰 (`04`) — Pod 삭제·replica 변경 수렴

## 2. 관찰한 증상 (사실만)

### lab 1 — API 요청
- `-v=9` 로그에서 본 왕복시간(`... OK in NN milliseconds`): ______ ms
- apiserver 매니페스트의 `--authorization-mode` 값: ______
- `--enable-admission-plugins` 에 있던 플러그인(아무거나 2~3개): ______
- 응답에서 본 `resourceVersion` 예시 값: ______

### lab 2 — etcd 저장 포맷
- etcdctl 실행 모드(스크립트가 출력): `node` / `crictl` 중 ______
- `/registry` 아래 총 키 개수(대략): ______
- Pod 값 앞부분 `od -c` 에서 본 매직 프리픽스: `______`  (힌트: 네 글자)
- 같은 Pod를 `-o json` 으로 보면? (한 줄 소감): ______

### lab 3 — scheduler 정지 중
- `sched-pending` 상태: ______ (예: Pending)  / `sched-pinned` 상태: ______ (예: Running)
- `sched-pending` 의 `.spec.nodeName`: ______  / `sched-pinned` 의 `.spec.nodeName`: ______
- scheduler 원복 후 `sched-pending` 은 어떻게 됐나: ______

### lab 4 — reconciliation
- Pod 하나 삭제 직후 `get pods` 에서 본 것(개수/상태): ______
- 다시 안정됐을 때 Pod 수: ______
- replicas 를 5→2 로 줄였을 때 초과 Pod는 어떻게 됐나: ______

## 3. 원인 가설과 검증

- `sched-pinned` 은 scheduler가 없는데도 왜 떴나(내 설명):
  > ______ (키워드: nodeName=Binding, kubelet, "누가 nodeName을 채우나")

- 내가 아무 이벤트도 보내지 않았는데 삭제한 Pod가 되살아난 이유(내 설명):
  > ______ (키워드: ReplicaSet 컨트롤러, 현재 vs 목표, level-triggered)

- kubectl은 JSON을 보여주는데 etcd 안은 바이너리(protobuf)였다. 이 "번역"은 누가 하나:
  > ______ (키워드: apiserver = etcd의 유일한 클라이언트/직렬화기)

## 4. 배운 트레이드오프
- **선언적 + level-triggered** vs edge-triggered(이벤트 기반):
  - 장점: ______  / 비용: ______ (힌트: 유실에 강함 vs 변화 감지 지연·디버깅 난도)
- **etcd(raft, 강한 일관성)**: 장점 ______ / 비용 ______ (힌트: 정합성 vs 쓰기성능·디스크지연 민감)
- **모놀리식 apiserver(단일 관문)**: 장점 ______ / 비용 ______ (힌트: 정책·감사 일원화 vs SPOF → HA는 복제로)

## 5. 완료 기준 — 질문에 답하기

**Q1. `kubectl apply` → 컨테이너 기동까지 컴포넌트 7개와 역할을 순서대로 설명하라.**
1. kube-apiserver: ______ (인증·인가·admission·검증 후 etcd 기록, 유일한 etcd 접점)
2. etcd: ______
3. kube-controller-manager (Deployment→ReplicaSet 컨트롤러): ______
4. kube-scheduler: ______ (nodeName 채우기 = Binding)
5. kubelet: ______
6. CRI / containerd: ______
7. kube-proxy: ______ (Service 트래픽 경로 — 자세한 건 Phase 3)
> 한 문단 서술:
> ______

**Q2. etcd 디스크가 느려지면 나타나는 증상 체인은?**
> apiserver 쓰기/읽기 지연 → ______ → 컨트롤러가 변화를 늦게 인지 → reconciliation 지연 → ______
> (키워드: apiserver가 etcd의 유일한 클라이언트, watch는 apiserver가 중계, `OK in NN ms` 가 커짐)

**Q3. resourceVersion과 optimistic concurrency가 동시 수정 충돌을 어떻게 막나?**
> ______
> (키워드: 모든 오브젝트에 resourceVersion(=etcd 리비전), update 시 내가 읽은 버전과 현재 버전이
>  다르면 409 Conflict → 클라이언트가 다시 읽고 재시도. 잠금 없이(낙관적) 충돌만 거부.)

---
_다음 Phase로 넘어가기 전에 Q1~Q3을 막힘없이 답할 수 있는지 확인._
