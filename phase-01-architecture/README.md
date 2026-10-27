# Phase 1 — 아키텍처 & 선언적 모델

> 목표: `kubectl apply` 이후 일어나는 일을 **컴포넌트 단위로 끝까지** 설명한다. 이 멘탈 모델이 이후 전부의 기반.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 1.

## 전제 (Phase 0 클러스터 재사용)

Phase 0에서 만든 kind 클러스터를 그대로 쓴다 — 새로 만들지 않는다.

- kubectl context: `kind-k8s-mastery`
- 노드: control-plane 1 + worker 3 (`k8s-mastery-control-plane`, `k8s-mastery-worker`, `-worker2`, `-worker3`)
- 필요한 것: `docker`(또는 호환 런타임), `kubectl`, 그리고 macOS 기본 `curl`/`od`

클러스터가 없다면 먼저:

```bash
bash phase-00-setup/scripts/01-create-cluster.sh
```

> 이 Phase의 랩은 각자 만든 리소스를 **끝에 스스로 정리**하고, 클러스터 자체는 건드리지 않는다
> (이후 Phase에서 계속 쓴다). 그래서 별도 cleanup 스크립트는 없다.

## 실습 순서

```bash
bash phase-01-architecture/scripts/01-observe-api-request.sh  # API 요청을 직접 관찰
bash phase-01-architecture/scripts/02-read-etcd.sh            # etcd에 저장된 바이트를 직접 열람
bash phase-01-architecture/scripts/03-stop-scheduler.sh       # (관찰) scheduler를 멈춰 역할 경계 확인
bash phase-01-architecture/scripts/04-reconciliation.sh       # (관찰) reconciliation/자가치유 체감
```

- `01`/`02`는 **탐색** 랩(내부를 들여다본다), `03`/`04`는 **관찰** 랩(조건을 바꿔 증상을 본다).
- `03`은 scheduler를 잠깐 내렸다가 **반드시 원복**한다(중간에 끊겨도 EXIT trap으로 복구). 따로 손댈 것 없다.

## 각 랩이 가르치는 것

- **lab 1 — API 요청 파이프라인.** `kubectl get --raw /api`·`/apis`로 "API는 그냥 REST 서버"임을 보고, `kubectl -v=9`로 클라이언트가 날리는 실제 HTTP(요청/응답 헤더·상태·왕복시간·resourceVersion)를 읽는다. control-plane 컨테이너의 `kube-apiserver.yaml`에서 `--authorization-mode`/`--enable-admission-plugins`/`--client-ca-file`/`--etcd-servers`를 꺼내 **인증 → 인가 → admission → etcd 저장** 파이프라인이 어디에 설정돼 있는지 확인. `kubectl proxy`로 API를 브라우징.
- **lab 2 — 저장 포맷.** control-plane 안의 `etcdctl`(ETCDCTL_API=3, cert는 `/etc/kubernetes/pki/etcd/*`)로 `/registry/...` 키 공간을 훑고, Pod 값의 실제 바이트를 `od -c`로 떠서 **protobuf 바이너리**(`k8s\0` 프리픽스)임을 확인. 같은 오브젝트를 `kubectl -o json`이 사람이 읽는 형태로 "번역"해 주는 것과 대조 → **apiserver가 etcd의 유일한 클라이언트이자 직렬화기**라는 사실.
- **lab 3 — scheduler의 역할 경계.** scheduler static pod를 내린 뒤, `nodeName` 없는 Pod는 Pending에 머물고 `nodeName`을 직접 박은 Pod는 뜨는 것을 관찰. → scheduler의 본질은 "적합한 노드를 골라 **nodeName(Binding)을 채우는 것**" 하나뿐이고, 실제 실행은 kubelet+CRI가 한다. 원복하면 Pending Pod가 저절로 스케줄되는 **수렴**도 본다.
- **lab 4 — 선언적 + level-triggered.** Deployment(Deployment → ReplicaSet → Pod 소유 체인)에서 Pod를 지우면 컨트롤러가 되살리고, replica 수를 바꾸면 양방향으로 수렴하는 것을 관찰. "이벤트"가 아니라 "현재 vs 목표" 비교로 동작함을 체감.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. `kubectl apply` → 컨테이너 기동까지 등장하는 **컴포넌트 7개**(kube-apiserver, etcd, kube-scheduler, kube-controller-manager, kubelet, kube-proxy, CRI/containerd)와 각자의 역할을 **순서대로** 설명할 수 있다.
2. **etcd 디스크가 느려지면** 나타나는 증상 체인을 설명할 수 있다 (watch 지연 → 컨트롤러 반응 지연 → …).
3. **resourceVersion**과 **optimistic concurrency**가 동시 수정 충돌을 어떻게 막는지 설명할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.
