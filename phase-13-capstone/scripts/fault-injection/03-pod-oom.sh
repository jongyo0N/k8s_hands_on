#!/usr/bin/env bash
# 캡스톤 장애주입 3 — 메모리 한도 초과 → OOMKilled 관찰
# 실행: bash scripts/fault-injection/03-pod-oom.sh
set -uo pipefail
CTX="kind-k8s-mastery"; NS="capstone"

echo "==> 장애 주입: memory limit 32Mi 인데 ~200Mi를 잡는 Pod"
kubectl --context "$CTX" -n "$NS" delete pod oom-demo --ignore-not-found >/dev/null 2>&1
cat <<'YAML' | kubectl --context "$CTX" -n "$NS" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
spec:
  restartPolicy: Always
  containers:
    - name: hog
      image: busybox:1.36
      # /dev/zero를 메모리에 적재해 한도를 초과시킨다
      command: ["sh","-c","tail /dev/zero | head -c 200m | sleep 600"]
      resources:
        limits:
          memory: "32Mi"
        requests:
          memory: "16Mi"
YAML

echo "==> 관찰: OOMKilled / exit 137 / 재시작"
for i in $(seq 1 6); do
  sleep 5
  kubectl --context "$CTX" -n "$NS" get pod oom-demo -o wide 2>/dev/null | grep -E 'NAME|oom-demo' || true
done
echo "    상세(Last State: OOMKilled, exit code 137 확인):"
kubectl --context "$CTX" -n "$NS" describe pod oom-demo 2>/dev/null | grep -A4 -E 'Last State|State:' | head -20 || true

echo
echo "==> 복구/정리"
kubectl --context "$CTX" -n "$NS" delete pod oom-demo --ignore-not-found >/dev/null

cat <<'EOF'
교훈: memory는 incompressible — 한도 초과 시 '즉시 kill'(CPU throttling과 대비, Phase 7).
복구는 limit 상향 또는 누수 수정. 재발방지는 VPA 추천 기반 right-sizing + 메모리 알림.
RUNBOOK 3번 항목을 채워보라.
EOF
