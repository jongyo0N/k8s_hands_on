# Phase 8 — NOTES (보안 & 하드닝)

> 방어 관점. ①적용한 통제 ②관찰(거부/허용) ③원인 ④트레이드오프를 적는다.

## 1. 무엇을 했는가
- [ ] PSA restricted 적용 → insecure Pod 거부 / hardened Pod 통과
- [ ] 최소 권한 RBAC + `auth can-i` 감사
- [ ] VAP(CEL) 레지스트리·latest 정책 집행
- [ ] 이미지 스캔(trivy) + 서명 검증(cosign) 게이트
- [ ] etcd encryption at rest + audit policy

## 2. 관찰 (사실만)
- `pod-insecure.yaml` 적용 결과: ______ (거부 사유 메시지?)
- `pod-hardened.yaml` 적용 결과: ______
- `kubectl auth can-i --list --as=system:serviceaccount:phase-08:____`: 과잉 권한 있었나? ______
- `:latest` 태그 Pod 적용 시 VAP 반응: ______
- 미서명 이미지 배포 시 Kyverno 반응: ______
- etcd에서 Secret: 암호화 전 ______ / 후 ______

## 3. 원인·이유
- restricted를 통과시키려고 추가한 securityContext 필드 목록과 각 이유:
  > runAsNonRoot: ____ / allowPrivilegeEscalation:false: ____ / capabilities drop ALL: ____ / seccompProfile: ____ / readOnlyRootFilesystem: ____

## 4. 트레이드오프
- 우리 조직엔 PSA/VAP로 충분한가, Kyverno가 필요한가? 판단 근거:
  > ______
- 정책을 enforce로 바로 켜는 것 vs audit→enforce 단계 도입:
  > ______

## 5. 완료 기준 — 답하기
1. 계층별 예방 통제 매핑 (인증/인가/admission/워크로드/노드/네트워크):
   > ______
2. restricted 통과 securityContext(빈 상태에서 작성):
   > ______
3. 예방(admission) vs 탐지(runtime) 역할 분담·도입 순서:
   > ______

---
_다음: Phase 9(관측성)로._
