# Phase 6 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] 준비 (`00-setup.sh`) — ns `phase-06` 생성
- [ ] ConfigMap env vs volume 전파 차이 (`01`)
- [ ] Reloader 자동 재시작 (`01b`)
- [ ] Secret 평문 확인 (`02`)
- [ ] encryption at rest 켜고 재확인 (`02b`) — provider: ______ (aescbc / secretbox)
- [ ] ESO 동기화/회전 (`03`)
- [ ] Helm vs Kustomize 렌더 비교 (`04`)

## 2. 관찰한 증상 (사실만)

### lab 1 — env vs volume
- ConfigMap을 v2로 바꾼 뒤, env 값: ______ (바뀜? 그대로?)
- 같은 시점 volume 파일 값: ______
- volume 파일이 v2로 바뀌기까지 걸린 시간(대략): ______ 초
- `01b` Reloader 적용 후 ConfigMap을 v3로: config-demo-reloader의 env 값: ______ (얼마 뒤 바뀜: ______)

### lab 2 — Secret in etcd
- 암호화 전 `02`: etcd hexdump에서 평문 `super-secret-password-123` 이 보였나? ______
- 암호화 후 `02b`: 값 앞 접두어 = ______ (예: `k8s:enc:aescbc:v1:key1:`), 평문이 사라졌나? ______

### lab 3 — ESO
- `demo-synced-secret` 이 생성되기까지: ______ 초
- fake provider 값을 v2로 바꾼 뒤 Secret이 갱신되기까지(대략): ______ 초 (refreshInterval=______)

### lab 4 — 렌더 비교
- Helm base vs prod: replicas ______ → ______, APP_ENV ______ → ______
- Kustomize dev vs prod: 이름 접두어 ______ / ______, replicas ______ / ______
- Kustomize가 configMapRef 이름을 자동으로 바꿔줬나(nameReference)? ______

## 3. 원인 가설과 검증
- env는 안 바뀌고 volume은 바뀐 이유(내 설명):
  > ______ (키워드: Pod 생성 시 복사 vs kubelet 주기적 동기화)
- base64 Secret이 "안전하지 않다"는 말의 정확한 의미(내 설명):
  > ______ (키워드: 인코딩 ≠ 암호화, etcd 평문 저장)
- encryption at rest를 켜도 '완전히' 안전하지 않은 이유(내 설명):
  > ______ (키워드: 키가 노드에 평문, KMS로 KEK 분리 필요)

## 4. 배운 트레이드오프
- 비밀 관리 4종(Sealed Secrets / ESO / Vault / SOPS) 중 내 상황엔 ______ 가 적합. 이유: ______
- Helm vs Kustomize — 이 앱 수준에선 ______ 로 충분. Helm이 정당화되는 지점: ______
- env vs volume 주입 — 내 앱은 ______ 선택. 이유: ______

## 5. 완료 기준 — 질문에 답하기

**Q1. "Secret은 안전한가?"를 계층별로 답하라.**
- 저장(at rest): ______
- 전송(in transit): ______
- 접근(access): ______
- 노드(node): ______

**Q2. 비밀 회전이 Pod까지 전파되는 전체 경로를 (ESO 기준) 설명하라.**
> 외부 저장소 회전 → ______ → ______ → (env면 ______ 필요 / volume·CSI면 ______)

**Q3. Helm의 복잡성이 정당화되는 조건 vs Kustomize로 충분한 조건은?**
> Helm: ______
> Kustomize: ______

**Q4. (보너스) ConfigMap을 env/volume로 주입하면 업데이트 전파가 왜 다른가?**
> ______

---
_다음 Phase로 넘어가기 전에 Q1~Q4를 막힘없이 답할 수 있는지 확인._
