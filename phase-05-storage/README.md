# Phase 5 — 스토리지

> 목표: CSI 파이프라인을 이해하고, 상태ful 워크로드의 배치 결정을 내릴 수 있다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 5.

## 사전 준비

Phase 0에서 만든 kind 멀티노드 클러스터(context `kind-k8s-mastery`, worker 3대)가 떠 있어야 한다.
없으면 먼저:

```bash
bash phase-00-setup/scripts/01-create-cluster.sh
```

그다음 Phase 5 준비(컨텍스트 확인 + namespace `phase-05` 생성 + 기본 SC 점검):

```bash
bash phase-05-storage/scripts/00-prep.sh
```

모든 스크립트는 `kubectl --context kind-k8s-mastery` 로 고정되어 있어, 현재 kubeconfig의
다른 컨텍스트를 건드리지 않는다. lab 4는 추가로 인터넷(operator 매니페스트 다운로드)이 필요하다.

## 실습 순서

```bash
bash phase-05-storage/scripts/00-prep.sh               # 0. 준비 + 기본 SC 점검
bash phase-05-storage/scripts/01-wffc-vs-immediate.sh  # 1. WFFC vs Immediate 바인딩 차이
bash phase-05-storage/scripts/02-csi-pipeline-trace.sh # 2. provision→attach→mount 추적
bash phase-05-storage/scripts/03-rwo-multiattach.sh    # 3. (관찰) RWO + 노드 drain
bash phase-05-storage/scripts/04-cnpg-failover.sh      # 4. CloudNativePG 페일오버
bash phase-05-storage/scripts/99-cleanup.sh            # (끝나면) Phase 5 리소스 정리
```

lab 1~3은 "일부러 실패를 관찰"하므로 `set -e` 없이(`set -uo pipefail`) 돈다.
lab 4의 operator/PostgreSQL 버전은 스크립트/매니페스트 상단에 핀되어 있다(최신은 주석의 링크로 확인).

- CloudNativePG operator: **v1.30.1** (`scripts/04-cnpg-failover.sh`)
- PostgreSQL 이미지: operator 기본값(= 버전에 핀). 고정하려면 `manifests/04-pg-cluster.yaml`의 `imageName` 주석 참고.

## 각 랩이 가르치는 것

- **lab 1 — WaitForFirstConsumer vs Immediate**: provisioner는 같고(`rancher.io/local-path`)
  `volumeBindingMode`만 다른 두 StorageClass로 PVC를 만든다. Immediate PVC는 소비 Pod가
  없어도 즉시 Bound(= 노드를 미리 고정), WFFC PVC는 `waiting for first consumer`로 Pending.
  이어서 Immediate PV가 묶인 노드를 피하도록 강제한 Pod가 `volume node affinity conflict`로
  스케줄에 실패하는 것을 관찰 → 멀티 AZ에서 Immediate가 깨뜨리는 제약을 체감. kind 기본
  `standard`가 이미 WFFC인 이유.

- **lab 2 — CSI 파이프라인 추적**: `standard`(WFFC) PVC + 소비 Pod로 **provision → attach →
  mount** 3단계를 `describe pvc/pv`, events, local-path-provisioner 로그, Pod의 VolumeMounts로
  추적. local-path는 CSI가 아니라 노드-로컬이라 **attach 단계(VolumeAttachment)가 없다**는 점을
  직접 확인하고, 진짜 CSI에서 attach가 어디서 나타나는지(external-attacher, `SuccessfulAttachVolume`)를
  대조한다.

- **lab 3 — RWO + 노드 장애 (관찰)**: RWO PVC를 쓰는 Deployment를 app-tier 워커에 고정 →
  그 노드를 `kubectl drain` → 데이터가 노드에 묶여 있어 새 Pod가 다른 노드로 못 가고
  `volume node affinity conflict`로 막히는 것을 관찰. 클라우드 CSI에서 같은 상황이
  `Multi-Attach error` + 강제 detach 타임아웃(~6분)으로 보인다는 것을 대조. uncordon으로 복구.
  (더 가혹한 `docker stop` 변형은 스크립트 주석 참고.)

- **lab 4 — CloudNativePG**: operator(버전 핀)를 server-side apply로 설치하고, 작은
  PostgreSQL `Cluster`(`postgresql.cnpg.io/v1`, instances 3)를 배포. primary Pod를 삭제해
  페일오버를 유발하고, operator가 standby를 새 primary로 승격(`status.currentPrimary` 변화)하는
  과정과 삭제된 인스턴스의 standby 재합류를 관찰.

## ⚖️ 트레이드오프 & 대안

- **local PV**: 최고 IOPS·지연 / 노드에 데이터 고정 → 노드 장애 = 데이터 접근 불가, 스케줄링 제약.
  **네트워크 스토리지(EBS류)**: 유연한 재attach / 지연·비용.
  **분산 스토리지(Ceph/Longhorn)**: 복제·유연성 / 운영 난도 최상급.
- **DB on k8s vs 매니지드 DB**: 운영 자동화·비용 절감·이식성 vs 운영 역량 요구·장애 책임.
  판단 기준: operator 성숙도, 팀의 스토리지 전문성, 백업·DR 검증 능력. "잘 모르겠으면 매니지드"가
  보수적 정답, 단 멀티클라우드·비용 압박·특수 요구는 반례.
- **백업 전략**: 스토리지 스냅샷(빠름, 앱 비인지) vs 논리 백업(pg_dump류, 복원 유연) vs
  operator 내장(WAL 아카이빙) — RPO/RTO로 결정.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. PVC 생성부터 컨테이너 마운트까지 CSI 컴포넌트별 단계(provision/attach/mount)를 설명할 수 있다.
2. `WaitForFirstConsumer`가 없으면 생기는 문제를 멀티 AZ 시나리오로 설명할 수 있다.
3. "우리 서비스 DB를 k8s로 옮기자"는 제안에 대한 찬반 논거를 각 3개씩 제시할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.
