# Phase 6 — 구성·시크릿·패키징

> 목표: 환경별 구성과 민감 정보를 안전하게 관리하고, 매니페스트 패키징 전략을 선택한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 6.

## 사전 준비

- Phase 0에서 만든 kind 클러스터가 떠 있어야 한다 (컨텍스트 `kind-k8s-mastery`, control-plane 컨테이너 `k8s-mastery-control-plane`).
  - 없으면: `bash phase-00-setup/scripts/01-create-cluster.sh`
- 도구: `kubectl`, `helm`(lab 1/3/4), `kustomize`(또는 `kubectl kustomize` 내장), `docker`(lab 2에서 etcd 직접 열기).

```bash
bash phase-06-config/scripts/00-setup.sh     # 컨텍스트/네임스페이스(phase-06)/도구 점검
```

모든 리소스는 네임스페이스 `phase-06` 에 만든다(operator는 각자 전용 네임스페이스).

## 실습 순서

```bash
bash phase-06-config/scripts/00-setup.sh                      # 0. 준비
bash phase-06-config/scripts/01-configmap-env-vs-volume.sh    # 1. env vs volume 전파 차이
bash phase-06-config/scripts/01b-install-reloader.sh          # 1. Reloader 자동 재시작
bash phase-06-config/scripts/02-secret-plaintext-etcd.sh      # 2. Secret 평문 확인(etcd 직접)
bash phase-06-config/scripts/02b-enable-encryption-at-rest.sh # 2. 암호화 켜기(⚠️ 파괴적, 선택)
bash phase-06-config/scripts/03-external-secrets-operator.sh  # 3. ESO 동기화/회전
bash phase-06-config/scripts/04-helm-vs-kustomize.sh          # 4. Helm vs Kustomize 렌더 비교
bash phase-06-config/scripts/99-cleanup.sh                    # (끝나면) 정리
```

> 💡 버전 핀: 스크립트 상단에 chart 버전을 고정해 두었다(`RELOADER_CHART_VERSION`, `ESO_CHART_VERSION`).
> 최신 확인은 각 스크립트 주석의 `helm search repo ... --versions` 명령으로.

## 각 랩이 가르치는 것

### lab 1 — ConfigMap 주입: env vs volume (`01`, `01b`)
- 같은 ConfigMap을 **env(valueFrom)** 와 **volume mount** 두 방식으로 동시에 주입한 뒤 ConfigMap을 수정한다.
- **결정적 차이**: env로 주입된 값은 Pod 생성 시 '복사'되어 **재시작 전엔 안 바뀐다**. volume은 kubelet이 주기적으로 갱신해 **일정 시간 뒤 파일이 바뀐다**(즉시는 아님).
- `01b`: **Reloader(stakater)** 를 설치하고 `reloader.stakater.com/auto: "true"` 를 단 Deployment가 ConfigMap 변경 시 **자동 롤링 재시작**되는 것을 관찰 → "env는 재시작 필요"의 실무적 해결.
- 보너스 개념: 안 바뀌는 설정은 `immutable: true` 로 두면 대규모에서 watch 부하를 줄인다.

### lab 2 — Secret은 평문이다 → encryption at rest (`02`, `02b`)
- `02`: Secret을 만들고 **etcd에서 직접** 읽어, base64가 '인코딩'일 뿐이며 etcd엔 **원문(평문)** 으로 들어감을 확인(`docker exec k8s-mastery-control-plane` → etcdctl → hexdump).
- `02b`(⚠️ 파괴적, 선택): **EncryptionConfiguration**(`apiserver.config.k8s.io/v1`, aescbc 또는 secretbox)을 노드에 심고 kube-apiserver static pod에 `--encryption-provider-config` 를 추가 → `kubectl get secrets -A -o json | kubectl replace -f -` 로 재암호화 → etcd에서 **암호문**(`k8s:enc:...` 접두어) 재확인.
- "Secret은 안전한가?"를 **계층**으로 답하는 훈련: 저장(at rest)/전송(TLS)/접근(RBAC)/노드(tmpfs).

### lab 3 — External Secrets Operator (`03`)
- **ESO**를 helm으로 설치(버전 핀)하고, 외부 시스템 없이 쓰는 **fake provider** `SecretStore` + `ExternalSecret`(`external-secrets.io/v1`)로 **외부 저장소 → k8s Secret 동기화**를 체험.
- provider의 값을 바꿔 **회전(rotation)** 이 `refreshInterval` 주기로 대상 Secret까지 전파되는 경로를 관찰.
- 실제론 provider 블록만 Vault/AWS SM/GCP SM/Kubernetes 등으로 교체하면 된다.

### lab 4 — Helm vs Kustomize (`04`)
- **같은 앱**을 (a) 최소 Helm 차트(`Chart.yaml`/`values.yaml`/`templates/`)와 (b) Kustomize base + dev/prod overlay로 각각 패키징.
- `helm template` 과 `kustomize build`(또는 `kubectl kustomize`) 렌더 결과를 비교: 템플릿 주입 vs 선언적 patch, 네이밍/네임스페이스/레플리카 분기 방식의 차이.

## ⚖️ 트레이드오프 & 대안

### 비밀 관리 4종 (판단축: "진실의 원천을 git에 둘까, 외부 저장소에 둘까")
| 방식 | 장점 | 비용 |
|---|---|---|
| **Sealed Secrets** | git에 '암호문'을 커밋(GitOps 친화), 단순 | 키 관리·회전 부담, 클러스터 종속 |
| **External Secrets Operator** | 외부 저장소가 진실의 원천, 회전 용이 | 외부 의존성 추가, operator 운영 |
| **Vault Agent/CSI** | 최강 기능, 동적 비밀(짧은 수명) | 운영 난도 높음 |
| **SOPS + Flux** | git 중심, 가벼움 | 복호화 키 배포 문제 |

### Helm vs Kustomize
- **Helm**: 템플릿 표현력, 패키지 배포, 버전/롤백. 단 YAML이 바로 안 보임(렌더 확인 필요).
- **Kustomize**: 템플릿 없는 단순성·가독성. 단 복잡한 분기/반복에는 표현력 부족.
- **실무 표준 패턴**: 서드파티는 Helm, 자체 앱은 Kustomize(또는 Helm 렌더 후 Kustomize 후처리). 대안: cdk8s/jsonnet/Timoni.
- ⚠️ **공급망**: 2025년 Bitnami 공개 차트·이미지 카탈로그가 대폭 축소됨 → '차트 출처·이미지 미러 전략'도 학습/설계 대상.

### env vs volume 주입
- 편의성(env) vs 갱신 가능성·노출면(volume). env는 crash dump·child process로 전파되기 쉬워 노출면이 넓다.

## 완료 기준 (NOTES.md에 답을 적을 것)

1. "Secret은 안전한가?"에 **계층별**(저장/전송/접근/노드)로 답할 수 있다.
2. 비밀 **회전**이 Pod까지 전파되는 전체 경로를, 선택한 도구(ESO 등) 기준으로 설명할 수 있다.
3. Helm 차트의 복잡성이 **정당화되는 조건**과 Kustomize로 **충분한 조건**을 구분할 수 있다.
4. (보너스) ConfigMap을 env/volume로 주입했을 때 업데이트 전파가 왜 다른지 설명할 수 있다.

## 산출물

관찰 결과와 완료 기준 답변을 [`NOTES.md`](./NOTES.md)에 기록한다. 이 기록이 포트폴리오가 된다.

## 디렉토리

```
phase-06-config/
├── README.md / NOTES.md
├── manifests/
│   ├── 01-config/        configmap.yaml, deployment.yaml, deployment-reloader.yaml
│   ├── 02-secret-encryption/  secret.yaml, encryption-config.aescbc.yaml, *.secretbox.yaml
│   ├── 03-eso/           secretstore-fake.yaml, externalsecret.yaml
│   └── 04-packaging/
│       ├── helm/myapp/   Chart.yaml, values.yaml, values-prod.yaml, templates/
│       └── kustomize/    base/ + overlays/{dev,prod}/
└── scripts/              00-setup ~ 04, 99-cleanup
```
