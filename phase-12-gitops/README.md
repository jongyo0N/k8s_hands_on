# Phase 12 — GitOps & 배포 파이프라인

> 목표: 선언적 배포를 git을 진실의 원천으로 자동화하고, 점진적 배포로 리스크를 통제한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 12.

## 사전 준비

Phase 0에서 만든 kind 클러스터(컨텍스트 `kind-k8s-mastery`)가 떠 있어야 한다. 도구/클러스터 점검:

```bash
bash phase-12-gitops/scripts/00-check-tools.sh
```

필수: `kubectl` `git` `curl` `python3`. 권장(없어도 kubectl로 대체 가능): `argocd` CLI, `kubectl-argo-rollouts` 플러그인, `kustomize`.

### ⚖️ GitOps(pull) vs CI push

| 선택 | 장점 | 비용 |
|---|---|---|
| **GitOps (pull)** — Argo CD/Flux가 클러스터 안에서 git을 당겨 동기화 | drift 자동 교정, 감사성(모든 변경이 git), 클러스터 자격증명 비노출 | 컨트롤러 운영 부담, 러닝커브 |
| **CI push** — 파이프라인이 밖에서 `kubectl/helm`으로 밀어넣음 | 단순함, 기존 CI 재사용 | "배포했지만 실제 상태는 모른다"(drift 무감지), CI에 클러스터 크리덴셜 노출 |

### ⚖️ Argo CD vs Flux

| 선택 | 장점 | 비용 |
|---|---|---|
| **Argo CD** | 강력한 UI·멀티테넌시·app-of-apps·직관성 | 상대적으로 무겁고 구성요소 많음 |
| **Flux** | 경량·조합형(GitOps Toolkit)·Kubernetes-native | UI 약함(별도), CRD 중심이라 초반 진입장벽 |

이 Phase는 **Argo CD**로 실습한다(UI 기반 가시성·app-of-apps가 학습에 유리). Flux는 개념 대조용으로 NOTES에 정리.

## GitOps 레포 설정 (중요)

Argo CD는 `kubectl apply`로 넘긴 YAML이 아니라 **git 레포를 직접 clone**해서 동기화한다. 그래서 매니페스트 안의 `repoURL`이 **실제로 접근 가능한 본인 레포**여야 한다.

- 기본값은 이 레포(`https://github.com/jongyo0N/k8s_hands_on.git`), `targetRevision: main`으로 되어 있다.
  이 PR을 `main`에 머지했고 당신이 이 레포 주인이면 **그대로 동작**한다.
- 포크했거나 다른 레포를 쓰면, `manifests/` 아래 `repoURL`을 전부 본인 레포로 바꾼다:

```bash
# <YOU>/<REPO> 를 본인 것으로 바꿔서 실행 (macOS BSD sed 기준: -i '')
grep -rl 'github.com/jongyo0N/k8s_hands_on' phase-12-gitops/manifests \
  | xargs sed -i '' 's|github.com/jongyo0N/k8s_hands_on|github.com/<YOU>/<REPO>|g'
```

- 아직 `main`에 머지 전이라면 `targetRevision`을 `phase-12-gitops` 브랜치로 바꿔도 된다.
- private 레포면 Argo CD에 repo credential을 등록해야 한다(`argocd repo add ...` 또는 repo Secret). 이 Phase의 기본은 public 가정.

## 실습 순서

```bash
bash phase-12-gitops/scripts/00-check-tools.sh            # 0. 도구/클러스터 점검
bash phase-12-gitops/scripts/01-install-argocd.sh         # 1. Argo CD 설치(버전 핀) + admin 비번
bash phase-12-gitops/scripts/01b-bootstrap-app-of-apps.sh # 1. app-of-apps 루트 부트스트랩
bash phase-12-gitops/scripts/02-drift-selfheal.sh         # 2. (관찰) drift 만들고 self-heal on/off 비교
bash phase-12-gitops/scripts/03-install-rollouts.sh       # 3. Argo Rollouts 설치 + Rollout/Analysis 배포
bash phase-12-gitops/scripts/03b-canary-observe.sh        # 3. (관찰) canary 트리거 + 단계/분석 관찰
bash phase-12-gitops/scripts/04-applicationset.sh         # 4. ApplicationSet로 dev/stg/prod 전개
bash phase-12-gitops/scripts/99-cleanup.sh                # (끝나면) 정리
```

버전을 고정하거나 바꾸고 싶으면:

```bash
ARGOCD_VERSION=v3.5.6   bash phase-12-gitops/scripts/01-install-argocd.sh
ROLLOUTS_VERSION=v1.10.1 bash phase-12-gitops/scripts/03-install-rollouts.sh
```

> 버전 핀은 작성 시점 최신(Argo CD `v3.5.6`, Argo Rollouts `v1.10.1`) 기준. 최신은 각 릴리스 페이지에서 재확인:
> <https://github.com/argoproj/argo-cd/releases> · <https://github.com/argoproj/argo-rollouts/releases>

## 각 랩이 가르치는 것

- **lab 1 — Argo CD 설치 + app-of-apps** (`01`, `01b`): 사람이 만드는 Application은 "루트" 하나뿐.
  루트가 git에서 자식 Application들을 읽어 apply하고, 자식이 다시 워크로드를 동기화하는 2단 reconciliation.
  "어떤 앱들이 클러스터에 있어야 하는가"까지 git으로 선언된다.
- **lab 2 — drift & self-heal** (`02`, 관찰): `kubectl`로 live를 바꿔 drift를 만든 뒤,
  Argo CD가 `OutOfSync`로 **감지**하는 것과 `selfHeal`로 **교정**하는 것을 분리해서 본다.
  `syncPolicy.automated`의 `prune`/`selfHeal` 의미와 "언제 selfHeal을 끄나"를 체감.
- **lab 3 — Argo Rollouts canary** (`03`, `03b`): `Deployment` 대신 `Rollout`으로
  `setWeight`/`pause` 단계적 배포 + Prometheus 메트릭 기반 `AnalysisTemplate`로 자동 승격/롤백.
  **메트릭이 선행되어야 자동 canary가 성립**함을 분석 실패 경로로 확인.
- **lab 4 — ApplicationSet** (`04`): `generator`(list/git)로 dev/stg/prod 3환경에 같은 앱을
  **파라미터만 바꿔** 전개. 디렉토리 per 환경 + kustomize 오버레이 + promotion 흐름.

## ⚖️ 그 밖의 트레이드오프

- **canary 자동화 vs 수동 승격**: 안전·빠른 롤백 vs 파이프라인·메트릭 신뢰도 요구. 메트릭이 부실하면 자동 canary는 오히려 위험하다.
- **브랜치 per 환경 vs 디렉토리 per 환경**: 익숙함 vs promotion 추적 용이성(현재는 디렉토리/overlay가 우세).
- **시크릿과 GitOps**: 평문 커밋은 금지. SOPS/age, Sealed Secrets, External Secrets Operator 등으로 "암호문만 git에, 평문은 클러스터에서"가 기본(Phase 6 연계). 각 방식의 신뢰 경계가 다르다.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. "git에 있는 것이 곧 클러스터 상태"가 깨지는 경우(drift·수동 변경)와 Argo CD의 처리 정책(감지 vs 교정, `prune`/`selfHeal`)을 설명할 수 있다.
2. canary 자동 롤백이 동작하려면 선행되어야 할 관측성 조건을 설명할 수 있다(메트릭 신뢰도·분석 실패 경로).
3. 시크릿을 GitOps에 통합하는 방법 3종(Sealed Secrets / SOPS / External Secrets)과 각 방식의 신뢰 경계를 설명할 수 있다.
4. GitOps(pull)와 CI push, Argo CD와 Flux의 트레이드오프를 각각 한 문장으로 방어할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.
