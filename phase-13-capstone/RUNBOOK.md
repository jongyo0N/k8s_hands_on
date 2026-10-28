# 캡스톤 런북 — 장애 대응

> 각 장애를 주입(`scripts/fault-injection/`)하고, 아래 표대로 진단→복구를 직접 수행하며 채운다.
> 운영 역량은 "증상에서 원인으로 가는 경로"를 아는 데서 나온다.

## 장애별 대응표

### 1. 워커 노드 다운 (`01-node-down.sh`)
| 단계 | 내용 |
|---|---|
| 증상 | 노드 `NotReady`, 해당 노드의 Pod가 `Terminating`/`Unknown`, 일정 시간 뒤 타 노드에 재생성 |
| 진단 | `kubectl get nodes`, `kubectl get pods -o wide -n capstone`, `kubectl describe node <n>` |
| 원인 | kubelet↔apiserver 하트비트 중단 → node controller가 `NotReady`→eviction |
| 복구 | 노드 복귀(`docker start`) 또는 재스케줄 완료 대기. PDB가 동시 축출을 제한 |
| 재발 방지 | multi-AZ topology spread + PDB + 충분한 replica; 노드 자동복구(ASG/Karpenter) |

### 2. DNS 장애 (`02-dns-outage.sh`)
| 단계 | 내용 |
|---|---|
| 증상 | 앱 로그에 이름해석 실패, 서비스 간 호출 타임아웃(IP 직접 호출은 됨) |
| 진단 | `kubectl -n kube-system get deploy coredns`, Pod에서 `nslookup`, CoreDNS 로그 |
| 원인 | CoreDNS 불가(스케일0/크래시) 또는 NetworkPolicy가 DNS egress 차단(Phase 4 함정) |
| 복구 | CoreDNS 복구(`scale --replicas`) 또는 DNS egress 허용 규칙 추가 |
| 재발 방지 | NodeLocal DNSCache, CoreDNS PDB/HPA, DNS egress 명시 허용 |

### 3. Pod OOMKilled (`03-pod-oom.sh`)
| 단계 | 내용 |
|---|---|
| 증상 | Pod `OOMKilled`, 재시작 반복(CrashLoopBackOff), exit code 137 |
| 진단 | `kubectl describe pod`(Last State: OOMKilled), 메모리 사용 vs limit |
| 원인 | 메모리 limit < 실사용. memory는 incompressible → 초과 시 즉시 kill(Phase 7) |
| 복구 | limit 상향 또는 누수 수정. QoS/우선순위 점검 |
| 재발 방지 | VPA 추천값 기반 right-sizing, 메모리 알림, 부하 테스트 |

### (추가) 인증서 만료 — Phase 10 참조
증상: kubectl/컴포넌트 통신 전면 실패 → `kubeadm certs check-expiration` → `renew all`.

## 증상별 트러블슈팅 플로우차트

```
Pod가 안 뜸?
├─ Pending ───────▶ describe: 스케줄 실패? (리소스 부족/taint/affinity/PVC 미바인딩)
├─ ContainerCreating ▶ describe/events: 이미지 pull? 볼륨 mount? CNI IP 할당?
├─ CrashLoopBackOff ▶ logs --previous: 앱 크래시? OOMKilled(137)? probe 실패?
└─ ImagePullBackOff ▶ 이미지/태그/레지스트리 인증 확인

네트워크 단절?
├─ DNS? ───────▶ CoreDNS 상태 + NetworkPolicy DNS egress
├─ Service? ────▶ EndpointSlice 비었나? (readiness 실패) / kube-proxy 규칙
└─ 외부? ───────▶ Gateway/HTTPRoute, LB, egress 정책

노드 NotReady? ─▶ kubelet 로그, 디스크/메모리 압박, CNI, 인증서

API 느림? ──────▶ etcd 디스크 지연, apiserver 부하, admission webhook 지연(Phase 11)
```
