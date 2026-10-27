# Phase 0 — NOTES

> 랩을 돌리며 ①무엇을 했는지 ②관찰한 증상 ③원인 가설과 검증 ④배운 트레이드오프를 적는다.
> 빈칸은 직접 채운다. "완료 기준" 질문에 소리 내어 답할 수 있어야 이 Phase가 끝난 것.

## 1. 무엇을 했는가
- [ ] 도구 점검 (`00-check-tools.sh`) — 런타임으로 ______ 선택 (이유: ______)
- [ ] 멀티노드 클러스터 생성 (`01`) — 노드 수: control-plane 1 + worker 3
- [ ] kubeconfig 인증 체인 확인 (`02`)
- [ ] control-plane 다운 관찰 (`03`)

## 2. 관찰한 증상 (사실만)

### lab 2 — 인증서 Subject
```
CN = ______            # RBAC가 보는 user
O  = ______            # RBAC가 보는 group
Issuer = ______
```
`kubectl auth can-i '*' '*' --all-namespaces` 결과: ______

### lab 3 — control-plane 정지 중
- `kubectl get nodes` 결과: ______ (예: 타임아웃/연결거부)
- 워커 containerd의 nginx 컨테이너 상태: ______ (Running? 사라짐?)
- control-plane 재기동 후 복구까지 걸린 시간(대략): ______ 초

## 3. 원인 가설과 검증

- control-plane이 꺼져도 nginx가 계속 돈 이유(내 설명):
  > ______

- 노드 라벨 중 kind-config의 `node-tier`는 붙었는데, `topology.kubernetes.io/zone`을
  굳이 `kubectl label`로 따로 붙인 이유(내 설명):
  > ______ (힌트: NodeRestriction, 노드가 "스스로" 붙일 수 있는 라벨의 범위)

## 4. 배운 트레이드오프
- 로컬 클러스터: kind vs minikube vs k3d — 내 상황에선 ______ 가 적합. 이유: ______
- 컨테이너 런타임: ______ 선택의 비용은 ______

## 5. 완료 기준 — 질문에 답하기

**Q1. kubeconfig의 user 인증 방식 3가지를 설명하라.**
1. 클라이언트 인증서: ______
2. bearer token: ______
3. exec plugin: ______ (언제 쓰나? 예: ______)

**Q2. control-plane이 내려가도 기존 Pod가 계속 도는 이유는?**
> ______
> (키워드: kubelet, containerd, 선언된 spec, "상태 변경 vs 상태 유지")

**Q3. (보너스) 노드가 스스로 붙일 수 없는 라벨이 있는 이유는?**
> ______

---
_다음 Phase로 넘어가기 전에 Q1~Q3을 막힘없이 답할 수 있는지 확인._
