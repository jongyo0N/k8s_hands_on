# Phase 10 — NOTES (수명주기 & 운영)

## 1. 무엇을 했는가
- [ ] HA 부트스트랩 절차 이해 (VM 전제)
- [ ] 업그레이드 체크리스트 숙지
- [ ] etcd snapshot 저장/복구
- [ ] 인증서 만료 확인/갱신

## 2. 관찰 (사실만)
- `kubeadm certs check-expiration` 결과(가장 임박한 만료): ______
- etcd snapshot 저장 경로/크기: ______
- 테스트 리소스 삭제 후 복구 시나리오에서 배운 점: ______

## 3. 원인·이유
- control-plane을 node보다 먼저 업그레이드하는 이유(skew):
  > ______
- etcd 백업만으로는 PV 데이터가 안 돌아오는 이유:
  > ______

## 4. 트레이드오프
- 우리 조직: managed vs self-managed — 선택과 근거:
  > ______
- in-place vs blue-green 업그레이드 — 이 클러스터엔:
  > ______

## 5. 완료 기준 — 답하기
1. 버전 skew 규칙 + control-plane 선행 이유:
   > ______
2. etcd 백업으로 복구되는 것 / 안 되는 것:
   > ______
3. "managed인데 왜 내부를 알아야 하나"의 반례:
   > ______

---
_다음: Phase 11(operator)로._
