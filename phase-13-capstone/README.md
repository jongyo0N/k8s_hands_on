# Phase 13 — 프로덕션 심화 & 캡스톤

> 목표: 앞선 모든 Phase를 하나의 프로덕션형 플랫폼으로 통합하고, 장애를 주입해 복구 런북을 쓴다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 13.

## 아키텍처

멀티티어 앱 — 스테이트리스 **API** + 상태ful **Store** — 을 하나의 kustomize 트리로 묶었다.

```
            Gateway(API) ──HTTPRoute──▶ api(Service/Deployment, HPA, PDB)
                                               │  (NetworkPolicy: default-deny + allow)
                                               ▼
                                         store(StatefulSet/Service, PDB)
   ServiceMonitor ──▶ Prometheus(Phase 9)
```

각 조각이 어느 Phase에서 왔는지:

| 리소스 | 역할 | 출처 Phase |
|---|---|---|
| `api-deployment` + restricted securityContext | 스테이트리스 서비스 · 워크로드 하드닝 | 2, 8 |
| `gateway` + `httproute` | L7 라우팅 | 4 |
| `networkpolicy` (default-deny + allow) | 네트워크 격리 | 4 |
| `store-statefulset` + `store-pdb` | 상태ful 저장소 · 가용성 | 2, 5 |
| `api-hpa` | 오토스케일링 | 7 |
| `api-pdb` | 무중단 노드 교체 | 7 |
| `api-servicemonitor` | 관측성 | 9 |
| overlays `dev`/`prod` | 환경 분기 | 6 |

## 배포

```bash
bash scripts/00-preflight.sh                      # 전제(클러스터·CRD) 점검
kubectl --context kind-k8s-mastery apply -k kustomize/overlays/dev
# 렌더 미리보기:
kustomize build kustomize/overlays/prod | less
```

> Gateway API/CNI(Phase 4), Prometheus(Phase 9)가 선행 설치돼 있어야 전부 동작한다. 없으면 해당 리소스는 Pending/무시된다 — preflight가 경고한다.

## 장애 주입 → 런북

[`RUNBOOK.md`](./RUNBOOK.md)에 "증상 → 진단 → 원인 → 복구 → 재발 방지" 표와 트러블슈팅 플로우차트가 있다. 주입 스크립트(각자 복구까지 포함):

```bash
bash scripts/fault-injection/01-node-down.sh      # 워커 노드 다운 → 재스케줄 관찰
bash scripts/fault-injection/02-dns-outage.sh     # CoreDNS 0 스케일 → 이름해석 장애
bash scripts/fault-injection/03-pod-oom.sh        # 메모리 한도 초과 → OOMKilled
```

## ⚖️ 트레이드오프 (종합)

- **비용 vs 안정성**: spot·공격적 consolidation·낮은 replica는 비용↓ 가용성↓. 워크로드 등급별 차등 정책이 현실적 타협.
- **플랫폼 추상화**: raw k8s 노출(유연·학습비용) vs 셀프서비스 플랫폼(생산성·가드레일 / 구축·유지보수 비용). 조직 규모가 임계점을 넘을 때 플랫폼팀이 정당화.
- **복잡도 그 자체**: 소규모·단순 워크로드엔 PaaS/서버리스/단일 VM이 나을 수 있다. **"언제 k8s를 쓰지 않을지"**를 아는 것이 마지막 교훈.

## 완료 기준 ([`NOTES.md`](./NOTES.md)에 답)

1. 이 플랫폼을 처음 보는 사람에게 15분 안에 아키텍처와 핵심 설계 결정을 트레이드오프와 함께 설명
2. 주입한 장애별 "증상 → 진단 → 원인 → 복구 → 재발 방지" 런북 제시
3. "이 조직엔 쿠버네티스가 과하다"가 참이 되는 조건을 구체적으로 제시

## 검증 수준
`kustomize build`(가능 시) + YAML 파싱 + 스크립트 `bash -n`. 이 환경엔 kind 미설치로 클러스터 실행은 미검증.
