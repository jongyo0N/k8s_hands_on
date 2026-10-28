# Phase 8 — 보안 & 하드닝

> 목표: 공격 표면을 계층별로 이해하고 각 계층을 **방어·하드닝·탐지**하는 통제를 설계·구현한다. (CKS 범위 + α)
> 이 Phase는 **전적으로 방어 관점**이다. 모든 랩은 보호 통제를 적용하고 그 효과를 검증한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 8.

## 전제
- Phase 0의 kind 클러스터(context `kind-k8s-mastery`), 네임스페이스 `phase-08`
- 일부 랩 도구: `trivy`, `cosign`, `kyverno`(클러스터), `jq`

## 실습 순서

```bash
bash scripts/00-check-tools.sh          # 도구 점검
bash scripts/01-psa-restricted.sh       # 1) Pod Security Admission: 하드닝으로 통과시키기
bash scripts/02-rbac-audit.sh           # 2) 최소 권한 RBAC + 권한 감사
bash scripts/03-vap-image-policy.sh     # 3) ValidatingAdmissionPolicy(CEL)로 조직 규칙 집행
bash scripts/04-supply-chain.sh         # 4) 이미지 스캔 + 서명 검증 게이트
bash scripts/05-etcd-audit.sh           # 5) etcd 암호화 + audit 정책
```

## 각 랩이 가르치는 것 (계층별 **예방** 통제)

| 랩 | 계층 | 통제 | 매니페스트 |
|---|---|---|---|
| 1 | 워크로드 | **PSA restricted** — 하드닝 안 된 Pod 거부 → securityContext(비root, cap drop ALL, seccomp, RO rootfs)로 통과 | `manifests/01-psa/` |
| 2 | 인가 | **최소 권한 RBAC** — 필요한 verb/resource만, `auth can-i`로 과잉 권한 감사 | `manifests/02-rbac/` |
| 3 | admission | **ValidatingAdmissionPolicy(CEL)** — 승인 레지스트리만·`:latest` 금지 | `manifests/03-vap/` |
| 4 | 공급망 | 이미지 **스캔(trivy)** + **서명 검증(cosign)**, 미서명 배포 차단(Kyverno) | `manifests/04-supply-chain/` |
| 5 | 저장/감사 | **etcd encryption at rest** + **audit policy** | `manifests/05-etcd-audit/` |

> 1번 랩의 `pod-insecure.yaml`은 **거부되는 것이 정상**이다(하드닝 전). `pod-hardened.yaml`이 restricted를 통과한다. 둘을 비교해 "restricted를 통과하는 securityContext"를 빈 상태에서 쓸 수 있게 되는 것이 목표.

## ⚖️ 트레이드오프 & 대안

- **정책 엔진 3종**: **PSA**(내장·간단 / 3단계 고정, 커스터마이즈 불가) vs **Kyverno**(YAML 정책·mutate/generate / 별도 컨트롤러) vs **OPA/Gatekeeper**(Rego 표현력 / 러닝커브). 단순 하드닝은 PSA+VAP로 충분, 복잡하면 Kyverno가 실무 기본값.
- **런타임 격리**: 일반 컨테이너(효율) vs gVisor(syscall 격리) vs Kata(경량 VM). 멀티테넌시·비신뢰 워크로드일수록 오른쪽. 대부분은 securityContext 하드닝 + 네트워크 격리로 충분.
- **예방 vs 탐지**: admission/PSA로 **예방**을 먼저 탄탄히, 런타임 탐지(Falco/Tetragon)는 그 위에. "예방 없이 탐지만"은 안티패턴.
- **보안 vs 개발 속도**: 강한 정책은 마찰을 만든다 → PSA/정책을 **audit 모드로 먼저 관찰 후 enforce**로 전환하는 단계적 도입이 정석.

## 완료 기준 ([`NOTES.md`](./NOTES.md)에 답)

1. 공격 표면을 계층(인증/인가/admission/워크로드/노드/네트워크)으로 나누고 각 계층의 **예방 통제**를 하나씩 매핑
2. restricted PSA를 통과하는 securityContext를 빈 상태에서 작성
3. "예방(admission) vs 탐지(runtime)"의 역할 분담과 도입 순서 설명

## 검증 수준
이 환경엔 kind 미설치 → 스크립트 `bash -n` + YAML 파싱만. 클러스터 실행 미검증. (랩 5의 encryption/audit은 kube-apiserver static pod 수정이 필요해 실제 적용 시 주의.)
