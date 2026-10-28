# Phase 11 — CRD · Operator · API 내부

> 목표: 쿠버네티스를 **플랫폼으로 확장**한다. `Website`라는 커스텀 리소스를 정의하고,
> 그것을 Deployment+Service로 수렴시키는 컨트롤러를 직접 돌리며 reconciliation을 몸으로 이해한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 11.

## 무엇을 만드는가

`Website` CR 하나(`image`/`host`/`replicas`/`port`)를 적으면 컨트롤러가 같은 이름의
**Deployment + Service**를 생성·동기화한다. 사용자는 "원하는 상태"만 선언하고, 세부 리소스는 operator가 책임진다.

```
Website(hello) ──reconcile──▶ Deployment(hello) + Service(hello)
   spec.image/replicas/port         ownerReference로 소유 → CR 삭제 시 GC
```

- CR 스키마: [`api/v1/website_types.go`](./api/v1/website_types.go) — 코드가 곧 스키마의 진실의 원천(`make manifests`가 CRD YAML 생성)
- 컨트롤러: [`internal/controller/website_controller.go`](./internal/controller/website_controller.go)
- 샘플 CR: [`config/samples/website.yaml`](./config/samples/website.yaml)

## 전제 도구

- Go (버전은 [`go.mod`](./go.mod) 참고), `kubebuilder`, `controller-gen`(Makefile이 자동 설치), `make`
- Phase 0의 kind 클러스터(context `kind-k8s-mastery`)

## 실행

이미 모든 소스가 들어 있으므로 스캐폴딩 없이 바로 돌릴 수 있다:

```bash
make manifests        # 마커 → CRD YAML 재생성 (config/crd/bases/…)
make install          # CRD를 클러스터에 등록
make run              # 컨트롤러를 로컬 프로세스로 실행 (빠른 개발 루프)
# 다른 터미널에서:
kubectl apply -f config/samples/website.yaml
kubectl get website,deploy,svc          # Website가 Deployment/Service를 낳았는지 확인
kubectl get website hello -o wide        # printer column(Host/Image/Desired/Ready/Phase)
```

클러스터 안에서 매니저로 돌리려면: `make docker-build docker-push IMG=...` 후 `make deploy IMG=...`.

> 처음부터 스캐폴딩을 연습하고 싶다면: `kubebuilder init --domain example.com --repo <mod>` →
> `kubebuilder create api --group apps --version v1 --kind Website`. 생성 파일을 이 레포의 것과 비교해보라.

## 랩 — 관찰 스크립트

```bash
bash scripts/01-observe-reconcile.sh    # reconcile가 도는 과정과 소유/자가치유 관찰
```

## 이 Phase의 핵심 (코드 주석 + NOTES에서 확인)

1. **멱등 · level-triggered** — reconcile는 "현재 spec을 보고 매번 재계산"한다. 이벤트 횟수에 의존하지 않기에, 중복 호출·유실에 강하다. 비멱등 reconcile(예: 매번 생성 시도)이 왜 깨지는지 주석으로 대조.
2. **ownerReference 기반 GC** — 생성한 Deployment/Service에 CR을 owner로 달아, CR을 지우면 가비지 컬렉터가 자식을 정리한다.
3. **finalizer** — 클러스터 밖 리소스(예: 외부 DNS 레코드)를 CR 삭제 전에 정리해야 할 때. finalizer가 없으면 외부 리소스가 누수된다.
4. **status subresource** — status 쓰기가 spec generation을 건드리지 않아 무한 루프를 막는다. `observedGeneration`으로 "반영 완료" 여부를 표현.
5. (개념) **admission webhook / conversion webhook / server-side apply field ownership** — README 아래 트레이드오프 참고.

## ⚖️ 트레이드오프 & 대안

- **operator를 만들 것인가**: 운영 지식의 코드화·자동화 / 비용: 개발·유지보수·버그가 곧 프로덕션 장애. 먼저 물어라 — Helm/Kustomize + 기존 operator로 충분한가? *"operator를 쓴다 ≠ operator를 만든다."*
- **작성 프레임워크**: controller-runtime/Kubebuilder(Go 표준·성숙 / Go 필요) vs Operator SDK(Ansible/Helm 기반 저코드 / 표현력 제한) vs Metacontroller·kube-rs(Rust)·shell-operator.
- **webhook의 리스크**: 강력한 통제 / webhook이 죽으면 관련 API 요청이 막혀 **클러스터 전체 장애**로 번질 수 있음 → `failurePolicy`·`timeoutSeconds`·네임스페이스 예외 설계가 필수.
- **CRD vs ConfigMap+컨트롤러 vs aggregated API**: 선언적 API의 정식화 vs 단순함 vs 완전한 제어(성능·스토리지 커스터마이즈).

## 완료 기준 ([`NOTES.md`](./NOTES.md)에 답)

1. reconcile 루프가 "level-triggered·멱등"이어야 하는 이유를 실패 사례로 설명
2. finalizer가 없을 때 생기는 리소스 누수 시나리오를 설명
3. admission webhook이 클러스터 가용성에 주는 리스크와 완화 설계를 설명

## 검증 수준

이 환경엔 kind·Go 툴체인 실행 제약이 있어 **정적 작성** 기준이다. 실제 클러스터에서 `make install && make run`으로 동작을 확인하라.
