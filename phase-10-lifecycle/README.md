# Phase 10 — 클러스터 수명주기 & 운영

> 목표: 클러스터를 만들고, 업그레이드하고, 백업·복구하고, 장애에 대응하는 운영 역량.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 10.

## ⚠️ 재현 전제

| 랩 | 어디서 | 이유 |
|---|---|---|
| 1 kubeadm HA 부트스트랩 | **VM 3대(multipass/VirtualBox 등)** | kind로는 진짜 HA control-plane(etcd 쿼럼·LB) 재현이 제한적 |
| 2 업그레이드 | VM 또는 kind | 체크리스트·순서 학습이 핵심 |
| 3 etcd snapshot | **kind에서 동작** | control-plane 컨테이너 안 etcdctl로 바로 가능 |
| 4 인증서 만료/갱신 | **kind에서 동작** | `kubeadm certs` 명령이 노드 이미지에 있음 |
| 5 vCluster(선택) | kind | 가상 control-plane 테넌트 격리 |

## 파일

- `manifests/kubeadm-config.yaml` — HA control-plane용 ClusterConfiguration(`controlPlaneEndpoint`=LB, stacked etcd)
- `manifests/haproxy.cfg` — control-plane 앞단 L4 로드밸런서 예시
- `manifests/kind-ha-config.yaml` — kind로 멀티 control-plane 흉내(학습용)
- `manifests/vcluster.yaml` — vCluster 값(선택 랩)
- `scripts/` — `00-check-tools`, `01a-ha-bootstrap`, `01b-ha-local-inspect`, `02-upgrade`, `03-etcd-snapshot`, `04-cert-expiry`

## 실습 순서

```bash
bash scripts/00-check-tools.sh
# 1) HA 부트스트랩 (VM 전제) — 절차/설정 이해
bash scripts/01a-ha-bootstrap.sh        # 실제 적용은 VM에서. 로컬 점검은 ↓
bash scripts/01b-ha-local-inspect.sh
# 2) 업그레이드 체크리스트 (control-plane → node 순서, skew 규칙)
bash scripts/02-upgrade.sh
# 3) etcd 백업/복구 (kind에서 동작)
bash scripts/03-etcd-snapshot.sh
# 4) 인증서 만료 확인/갱신 (kind에서 동작)
bash scripts/04-cert-expiry.sh
```

## 핵심 개념

- **버전 skew & 업그레이드 순서**: control-plane을 먼저, 그다음 node. kubelet은 apiserver보다 최대 몇 마이너 낮아도 되지만 높으면 안 된다 → 그래서 control-plane이 선행.
- **etcd 백업의 경계**: etcd snapshot은 "클러스터 오브젝트"를 복구한다. **PV 안의 실제 데이터는 복구하지 않는다**(별도 스토리지 백업 필요).
- **인증서 수명주기**: kubeadm 인증서는 1년 만기(기본). 만료되면 apiserver/kubelet 통신이 끊겨 전면 장애 → 갱신 자동화 필요.

## ⚖️ 트레이드오프 & 대안

- **managed(EKS/GKE/AKS) vs self-managed(kubeadm/kops/Cluster API)**: control-plane 운영 부담 제거·SLA vs 완전한 통제·비용 최적화·이식성. 대부분 managed가 기본값, self-managed는 규제·온프렘·특수 요구일 때.
- **업그레이드 전략**: in-place(단순 / 롤백 어려움) vs blue-green 클러스터(안전한 롤백 / 2배 비용).
- **멀티테넌시 격리**: 네임스페이스(가벼움/약한 격리) vs vCluster(가상 control-plane/오버헤드) vs 물리 분리(강한 격리/비용 폭증).

## 완료 기준 ([`NOTES.md`](./NOTES.md)에 답)

1. 버전 skew 규칙과 왜 control-plane을 먼저 올리는지
2. etcd 백업으로 복구되는 것과 안 되는 것(PV 데이터 등) 구분
3. "managed를 쓰는데 왜 내부를 알아야 하나"에 반례로 답

## 검증 수준
스크립트 `bash -n` + YAML 파싱만. HA 부트스트랩/업그레이드는 VM 전제라 미실행. etcd snapshot·cert 확인은 kind에서 동작하도록 작성(이 환경엔 kind 미설치로 실행은 미검증).
