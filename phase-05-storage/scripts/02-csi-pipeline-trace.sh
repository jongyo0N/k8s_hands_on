#!/usr/bin/env bash
# Phase 5 / lab 2 — CSI 파이프라인 추적: provision → attach → mount (관찰 랩)
# 질문: PVC 하나가 컨테이너 안 디렉터리가 되기까지 어떤 단계를 거치나?
# 실행: bash phase-05-storage/scripts/02-csi-pipeline-trace.sh
#
# 주의: -e 안 켬. 중간 get/describe/logs가 타이밍상 비어 있을 수 있어 관찰만 한다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CTX="kind-k8s-mastery"
NS="phase-05"
LP_NS="local-path-storage"   # kind의 local-path-provisioner가 사는 namespace

kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f - >/dev/null 2>&1 || true

echo "==> 1) PVC 생성 (standard=WFFC). 소비 Pod가 없으니 아직 Pending 이어야 한다."
kubectl --context "${CTX}" apply -f "${MANIFESTS}/02-pvc-standard.yaml"
sleep 2
kubectl --context "${CTX}" -n "${NS}" get pvc trace-pvc

echo
echo "==> 2) 소비 Pod 생성 → 이 순간 [provision] 단계가 시작된다"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/02-pod-consumer.yaml"
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Ready pod/trace-pod --timeout=120s || true

echo
echo "==> 3) [PROVISION] PVC events — WFFC 대기 → provisioning → 성공 흐름"
kubectl --context "${CTX}" -n "${NS}" describe pvc trace-pvc | sed -n '/Events:/,$p'
echo
echo "    생성된 PV:"
kubectl --context "${CTX}" -n "${NS}" get pvc trace-pvc \
  -o custom-columns='PVC:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,SC:.spec.storageClassName'

echo
echo "==> 4) [PROVISION] provisioner 로그 — local-path는 helper Pod로 노드에 디렉터리를 만든다"
echo "    (rancher.io/local-path provisioner, namespace=${LP_NS})"
kubectl --context "${CTX}" -n "${LP_NS}" logs deploy/local-path-provisioner --tail=30 2>/dev/null \
  | grep -Ei 'provision|trace-pvc|created|helper|path' \
  || echo "    (로그가 비었거나 이미 롤오버됨 — describe의 events로도 provision 확인 가능)"

echo
echo "==> 5) [ATTACH] local-path는 CSI가 아니다 → VolumeAttachment가 '없다'"
kubectl --context "${CTX}" get volumeattachment 2>/dev/null || true
cat <<'EOF'
    해석: rancher.io/local-path는 CSI 드라이버가 아니라 노드-로컬 hostPath를 쓴다.
          데이터가 노드에 붙박이라 "attach(노드에 블록장치 붙이기)" 단계 자체가 없다.
          → 따라서 VolumeAttachment 객체도, external-attacher 사이드카도 등장하지 않는다.

    진짜 CSI(예: EBS/openebs)에서 attach는 이렇게 보인다(개념):
      - controller plugin + external-attacher 사이드카가 VolumeAttachment를 처리
      - 성공 시 Pod events에 "SuccessfulAttachVolume"
      - 노드 간 이동 시 여기서 지연/Multi-Attach가 발생 (lab 3에서 그 증상을 관찰)
EOF

echo
echo "==> 6) [MOUNT] kubelet이 PV를 컨테이너에 bind mount — Pod events / 볼륨 구성"
kubectl --context "${CTX}" -n "${NS}" describe pod trace-pod | sed -n '/Events:/,$p'
echo
echo "    Pod가 실제로 보는 볼륨 소스 / 마운트 경로:"
kubectl --context "${CTX}" -n "${NS}" get pod trace-pod \
  -o jsonpath='{range .spec.volumes[*]}{"volume="}{.name}{" claim="}{.persistentVolumeClaim.claimName}{"\n"}{end}'
kubectl --context "${CTX}" -n "${NS}" get pod trace-pod \
  -o jsonpath='{range .spec.containers[*]}{"container="}{.name}{" mountPath="}{.volumeMounts[?(@.name=="data")].mountPath}{"\n"}{end}'

echo
echo "==> 7) PV의 실체 — hostPath + nodeAffinity (데이터가 노드에 묶인 증거)"
PV_TRACE="$(kubectl --context "${CTX}" -n "${NS}" get pvc trace-pvc -o jsonpath='{.spec.volumeName}' 2>/dev/null)"
if [ -n "${PV_TRACE}" ]; then
  kubectl --context "${CTX}" get pv "${PV_TRACE}" \
    -o jsonpath='{"hostPath="}{.spec.hostPath.path}{.spec.local.path}{"\nnode="}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}'
fi

cat <<'EOF'

    정리 — PVC가 컨테이너 디렉터리가 되기까지:
      1) provision: (WFFC는 Pod 스케줄 후) provisioner가 PV 실체를 만든다
      2) attach:    CSI라면 노드에 볼륨을 붙인다 (local-path는 이 단계 없음)
      3) mount:     kubelet(+ CSI node plugin)이 Pod의 mountPath에 올린다
    (NOTES.md에 각 단계의 담당 컴포넌트를 적어보라.)
EOF

echo
echo "다음: bash phase-05-storage/scripts/03-rwo-multiattach.sh"
