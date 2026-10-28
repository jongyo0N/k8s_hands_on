#!/usr/bin/env bash
# Phase 5 / lab 1 — WaitForFirstConsumer vs Immediate (관찰 랩)
# 질문: 바인딩 모드만 바꾸면 PVC 바인딩/스케줄링이 어떻게 달라지는가?
# 실행: bash phase-05-storage/scripts/01-wffc-vs-immediate.sh
#
# 주의: -e를 켜지 않는다. "일부러 스케줄 실패하는" Pod를 관찰하기 때문.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests"
CTX="kind-k8s-mastery"
NS="phase-05"

kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f - >/dev/null 2>&1 || true

echo "==> 1) StorageClass 2개 생성 (provisioner 동일, 바인딩 모드만 다름)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-storageclass-immediate.yaml"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-storageclass-wffc.yaml"
kubectl --context "${CTX}" get storageclass phase05-local-immediate phase05-local-wffc \
  -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner,BINDINGMODE:.volumeBindingMode'

echo
echo "==> 2) PVC 2개 생성 — 소비 Pod는 아직 없음"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-pvc-immediate.yaml"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-pvc-wffc.yaml"

# Immediate는 즉시 provision을 시도하므로 Bound까지 잠깐 기다려 본다(실패해도 계속 진행).
kubectl --context "${CTX}" -n "${NS}" wait --for=jsonpath='{.status.phase}'=Bound \
  pvc/pvc-immediate --timeout=60s || true

echo
echo "==> 3) 핵심 관찰: 소비 Pod가 없는데도 상태가 갈린다"
kubectl --context "${CTX}" -n "${NS}" get pvc pvc-immediate pvc-wffc
cat <<'EOF'
    기대 결과:
      pvc-immediate   Bound     <- Pod가 없어도 즉시 바인딩됨
      pvc-wffc        Pending   <- 소비 Pod를 기다리는 중
EOF

echo
echo "==> 4) WFFC PVC는 왜 Pending인가? events 확인"
kubectl --context "${CTX}" -n "${NS}" describe pvc pvc-wffc | sed -n '/Events:/,$p'
echo "    ^ 'waiting for first consumer to be created before binding' 가 보여야 한다."

echo
echo "==> 5) Immediate PVC가 묶인 PV와 그 nodeAffinity (= 미리 고른 노드)"
PV_IMM="$(kubectl --context "${CTX}" -n "${NS}" get pvc pvc-immediate -o jsonpath='{.spec.volumeName}' 2>/dev/null)"
if [ -n "${PV_IMM}" ]; then
  kubectl --context "${CTX}" get pv "${PV_IMM}" \
    -o custom-columns='PV:.metadata.name,CLAIM:.spec.claimRef.name,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase'
  PINNED_NODE="$(kubectl --context "${CTX}" get pv "${PV_IMM}" \
    -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null)"
  echo "    이 PV는 노드 '${PINNED_NODE:-?}' 에 nodeAffinity로 고정됨 (Pod도 없이 결정된 값!)."
else
  PINNED_NODE=""
  echo "    pvc-immediate가 아직 Bound되지 않았다(이 kind 이미지의 local-path가 Immediate를"
  echo "    처리하는 방식에 따라 다를 수 있음). 그래도 lab의 핵심(WFFC=Pending)은 위에서 확인됨."
fi

echo
echo "==> 6) [노드 제약 깨짐] Immediate PV의 노드를 '피하도록' 한 Pod를 만들어 본다"
if [ -n "${PINNED_NODE}" ]; then
  cat <<YAML | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: immediate-conflict
  namespace: ${NS}
spec:
  # PV가 고정된 노드(${PINNED_NODE})가 아닌 곳에만 스케줄되도록 강제 → 볼륨과 충돌 유도
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: kubernetes.io/hostname
                operator: NotIn
                values: ["${PINNED_NODE}"]
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: pvc-immediate
YAML
  sleep 8
  echo
  echo "    immediate-conflict Pod 상태 / events:"
  kubectl --context "${CTX}" -n "${NS}" get pod immediate-conflict -o wide
  kubectl --context "${CTX}" -n "${NS}" describe pod immediate-conflict | sed -n '/Events:/,$p'
  echo "    ^ 'volume node affinity conflict' (또는 FailedScheduling)이 보여야 한다."
  echo "      = 멀티 AZ에서 Immediate가 노드를 먼저 박아버려 Pod가 갈 곳을 잃는 바로 그 증상."
else
  echo "    (pvc-immediate 미바인딩으로 이 단계는 건너뜀)"
fi

echo
echo "==> 7) [대조] WFFC는 Pod를 따라간다 — 소비 Pod를 만들면 그때 바인딩"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-pod-wffc-consumer.yaml"
kubectl --context "${CTX}" -n "${NS}" wait --for=condition=Ready pod/wffc-consumer --timeout=90s || true
echo
echo "    이제 pvc-wffc가 Bound로 바뀌었는지 확인:"
kubectl --context "${CTX}" -n "${NS}" get pvc pvc-wffc
kubectl --context "${CTX}" -n "${NS}" get pod wffc-consumer -o wide

cat <<'EOF'

    정리:
      - Immediate:  바인딩이 "Pod보다 먼저" → 노드/AZ를 미리 박음 → 제약 충돌 위험.
      - WFFC:       바인딩이 "Pod 스케줄 이후" → 볼륨이 Pod를 따라감 → 제약이 안 깨짐.
      kind 기본 'standard'가 WFFC인 이유가 이것. (NOTES.md에 멀티 AZ 시나리오로 설명해보라.)
EOF

echo
echo "다음: bash phase-05-storage/scripts/02-csi-pipeline-trace.sh"
