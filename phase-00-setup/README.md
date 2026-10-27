# Phase 0 — 환경 구축 & 도구

> 목표: 1분 안에 멀티노드 클러스터를 만들고 지울 수 있는 로컬 환경.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 0.

## 사전 준비

컨테이너 런타임 하나 + kind + kubectl + openssl 이 필요하다. 먼저 점검:

```bash
bash phase-00-setup/scripts/00-check-tools.sh
```

없는 도구는 스크립트가 출력하는 Homebrew 힌트로 설치한다.

### ⚖️ 컨테이너 런타임 선택 (macOS)

| 선택 | 장점 | 비용 |
|---|---|---|
| **OrbStack** | 가볍고 빠름, 배터리 효율 | 상용(개인 무료 티어), 비교적 신생 |
| **Docker Desktop** | 사실상 표준, 생태계 호환 | 무거움, 대기업 유료 |
| **Colima** | 무료 OSS, CLI 친화 | 설정 수동, GUI 없음 |

kind 자체는 셋 다에서 동작한다. 결정 기준: 팀 표준 호환이 중요하면 Docker Desktop, 로컬 속도가 중요하면 OrbStack, 라이선스·비용 회피가 중요하면 Colima.

## 실습 순서

```bash
bash phase-00-setup/scripts/00-check-tools.sh        # 0. 도구 점검
bash phase-00-setup/scripts/01-create-cluster.sh     # 1. 멀티노드 클러스터 생성 + 라벨링
bash phase-00-setup/scripts/02-inspect-kubeconfig.sh # 2. 인증 체인 뜯어보기
bash phase-00-setup/scripts/03-controlplane-failure.sh # 3. control-plane 다운 관찰
bash phase-00-setup/scripts/99-cleanup.sh            # (끝나면) 클러스터 삭제
```

버전을 고정하고 싶으면:

```bash
KIND_IMAGE=kindest/node:v1.33.0 bash phase-00-setup/scripts/01-create-cluster.sh
```

## 각 랩이 가르치는 것

- **lab 1** — kind 멀티노드(`kind-config.yaml`), 노드 라벨. 커스텀 라벨(kind가 kubelet 경로로)과 예약 라벨 `topology.kubernetes.io/zone`(관리자 경로로)의 차이 → NodeRestriction admission을 체감.
- **lab 2** — kubeconfig의 cluster/user/context 구조. 클라이언트 인증서 Subject를 디코드해 `CN`(user)·`O`(group)이 RBAC와 어떻게 연결되는지 확인. 인증 방식 3종(cert/token/exec plugin).
- **lab 3** — control-plane 컨테이너를 멈추고, (a) kubectl이 죽는 것과 (b) 기존 워크로드는 containerd 위에서 계속 도는 것을 **직접** 관찰. "control-plane = 상태를 바꾸는 주체"라는 멘탈 모델.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. kubeconfig의 user 인증 방식 3가지(클라이언트 인증서, bearer token, exec plugin)를 설명할 수 있다.
2. control-plane이 내려가도 기존 Pod가 계속 도는 이유를, kubelet·containerd·control-plane 역할 분담으로 설명할 수 있다.
3. (보너스) 노드가 스스로 붙일 수 없는 라벨이 있는 이유(NodeRestriction)를 설명할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.
