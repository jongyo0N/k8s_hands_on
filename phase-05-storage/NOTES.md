# Phase 5 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] 준비 + 기본 SC 점검 (`00-prep.sh`) — `standard`의 bindingMode: ______
- [ ] WFFC vs Immediate (`01`)
- [ ] CSI 파이프라인 추적 (`02`)
- [ ] RWO + 노드 drain 관찰 (`03`)
- [ ] CloudNativePG 페일오버 (`04`)

## 2. 관찰한 증상 (사실만)

### lab 1 — 바인딩 모드 차이
```
kubectl get pvc 결과:
  pvc-immediate   -> ______   (Bound? Pending?)
  pvc-wffc        -> ______

pvc-wffc describe의 Events 메시지: ______
Immediate PV가 미리 고정한 노드: ______
immediate-conflict Pod의 FailedScheduling 사유: ______
```

### lab 2 — provision → attach → mount
```
provision: PVC events 순서 ______ -> ______ -> ______
           local-path-provisioner 로그에서 본 것: ______
attach:    kubectl get volumeattachment 결과: ______  (왜 이런가? ______)
mount:     trace-pod의 mountPath ______, 볼륨 소스(claim) ______
PV 실체:   hostPath ______ / nodeAffinity node ______
```

### lab 3 — RWO + drain 타임라인
- Pod가 처음 뜬 노드: ______
- drain 직후 새 Pod 상태: ______ (사유 메시지: ______)
- uncordon 후 Pod가 다시 뜬 노드: ______ (왜 하필 이 노드? ______)
- heartbeat.log 라인 수 (복구 후): ______ (데이터 보존됐나? ______)

### lab 4 — CloudNativePG 페일오버
- 초기 currentPrimary: ______
- primary Pod 삭제 후 currentPrimary: ______ (바뀌기까지 대략: ______ 초)
- 삭제됐던 인스턴스는 어떤 역할로 재합류했나: ______

## 3. 원인 가설과 검증

- Immediate가 멀티 AZ에서 위험한 이유(내 설명):
  > ______ (키워드: Pod 없이 노드/zone 선점, volume node affinity conflict)

- local-path에 attach 단계가 없는 이유(내 설명):
  > ______ (키워드: CSI 아님, 노드-로컬 hostPath, bind mount)

- RWO Pod가 다른 노드에서 바로 못 뜨는 이유(내 설명):
  > ______ (키워드: 노드 단위 단일 attach, 데이터가 Pod를 따라오지 않음, 클라우드의 Multi-Attach/강제 detach 타임아웃)

## 4. 배운 트레이드오프
- 스토리지 선택: local PV vs 네트워크(EBS류) vs 분산(Ceph/Longhorn) — 내 상황에선 ______ 가 적합. 이유: ______
- 백업 전략: 스냅샷 vs 논리백업 vs WAL 아카이빙 — 내 RPO/RTO엔 ______

## 5. 완료 기준 — 질문에 답하기

**Q1. PVC 생성부터 컨테이너 마운트까지 CSI 컴포넌트별 단계를 설명하라.**
1. provision: ______ (담당: external-provisioner / provisioner)
2. attach: ______ (담당: controller plugin + external-attacher, VolumeAttachment)
3. mount: ______ (담당: kubelet + node plugin)

**Q2. WaitForFirstConsumer가 없으면(=Immediate) 생기는 문제를 멀티 AZ로 설명하라.**
> ______
> (키워드: 바인딩이 스케줄보다 먼저, zone 선점, Pod가 갈 노드를 잃음)

**Q3. "우리 서비스 DB를 k8s로 옮기자" — 찬반 논거 각 3개.**
- 찬성: 1) ______  2) ______  3) ______
- 반대: 1) ______  2) ______  3) ______
- 내 결론과 조건: ______

---
_다음 Phase로 넘어가기 전에 Q1~Q3을 막힘없이 답할 수 있는지 확인._
