# Phase 11 — NOTES

> ①무엇을 했는지 ②관찰 ③원인·이유 ④트레이드오프를 적는다. 완료 기준에 소리내어 답해야 끝.

## 1. 무엇을 했는가
- [ ] `make manifests && make install` — CRD 등록
- [ ] `make run` — 컨트롤러 로컬 실행
- [ ] `kubectl apply -f config/samples/website.yaml` — CR 적용
- [ ] Website → Deployment/Service 생성 확인
- [ ] CR 삭제 → 자식 리소스 GC 관찰

## 2. 관찰한 것 (사실만)
- `kubectl get website hello -o wide` printer column: Host=____ Image=____ Desired=____ Ready=____ Phase=____
- CR 적용 후 생성된 리소스: Deployment ____ / Service ____
- CR의 `replicas`를 바꿨을 때 Deployment가 수렴하기까지: ____
- Deployment를 수동으로 지웠을 때(자가치유): ____
- CR을 지웠을 때 Deployment/Service: ____ (ownerReference GC)
- `spec.host: ""`로 적용 시도: ____ (API server 거부?)

## 3. 원인·이유
- reconcile를 여러 번 호출해도 결과가 같은 이유(멱등):
  > ____
- status를 subresource로 분리한 덕에 무한 루프가 안 생기는 이유:
  > ____ (spec generation vs status 쓰기)

## 4. 배운 트레이드오프
- 이 기능을 operator로 만드는 게 정당한가, 아니면 Helm/기존 operator로 충분한가? 내 판단:
  > ____
- webhook을 붙일 때 `failurePolicy`를 Fail로 둘지 Ignore로 둘지의 트레이드오프:
  > ____

## 5. 완료 기준 — 답하기
1. reconcile가 level-triggered·멱등이어야 하는 이유(비멱등 실패 사례):
   > ____
2. finalizer 없을 때의 리소스 누수 시나리오:
   > ____
3. admission webhook의 가용성 리스크와 완화(failurePolicy/timeout/네임스페이스 예외):
   > ____

---
_다음: Phase 12(GitOps)로._
