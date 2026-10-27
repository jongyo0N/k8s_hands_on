#!/usr/bin/env bash
# Phase 6 / lab 1 (이어서) — Reloader(stakater)로 ConfigMap 변경 시 '자동 재시작'
#   env 주입의 한계("재시작해야 반영")를 Reloader가 어떻게 메우는지 관찰한다.
# 실행: bash phase-06-config/scripts/01b-install-reloader.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests/01-config"
CTX="kind-k8s-mastery"
NS="phase-06"
K="kubectl --context ${CTX} -n ${NS}"

# 버전 핀. 최신 확인: helm repo add stakater https://stakater.github.io/stakater-charts && \
#                     helm repo update && helm search repo stakater/reloader --versions | head
RELOADER_CHART_VERSION="2.2.18"   # chart 2.2.18 = app v1.4.22 (2025-10 기준 최신 근처)

command -v helm >/dev/null 2>&1 || { echo "[에러] helm 필요: brew install helm"; exit 1; }

echo "==> 1) stakater helm repo 추가/갱신"
helm repo add stakater https://stakater.github.io/stakater-charts >/dev/null 2>&1 || true
helm repo update stakater >/dev/null

echo
echo "==> 2) Reloader 설치 (namespace: reloader, chart ${RELOADER_CHART_VERSION})"
helm upgrade --install reloader stakater/reloader \
  --kube-context "${CTX}" \
  --namespace reloader --create-namespace \
  --version "${RELOADER_CHART_VERSION}" \
  --wait --timeout 180s

echo
echo "==> 3) 자동 재시작 대상 Deployment 적용 (annotation reloader.stakater.com/auto=true)"
$K apply -f "${MANIFESTS}/deployment-reloader.yaml"
$K rollout status deployment/config-demo-reloader --timeout=120s
sleep 5
echo "    현재 값:"
$K logs deploy/config-demo-reloader --tail=1

echo
echo "==> 4) ConfigMap을 v3로 수정 → Reloader가 config-demo-reloader를 자동 롤링 재시작하는지 관찰"
$K patch configmap app-config --type merge -p '{"data":{"GREETING":"v3 (reloader!)"}}'
echo "    (Reloader가 감지 후 재시작을 트리거하기까지 수 초~수십 초)"
for i in $(seq 1 24); do
  line="$($K logs deploy/config-demo-reloader --tail=1 2>/dev/null || true)"
  echo "    [t=$((i * 5))s] ${line}"
  if echo "${line}" | grep -q 'v3'; then
    echo "    -> env 값이 v3로 갱신! Reloader가 새 Pod를 띄워 env 주입값까지 반영됨."
    break
  fi
  sleep 5
done

cat <<'EOF'

    해석:
      - annotation(reloader.stakater.com/auto=true)이 달린 워크로드는, 그것이 '참조하는'
        ConfigMap/Secret이 바뀌면 Reloader가 pod template을 건드려 롤링 재시작을 건다.
      - 그래서 env 주입이라도 설정 변경이 '새 Pod'에 반영된다 → "env는 재시작 필요"의 자동화.
      - 특정 리소스만 보려면: configmap.reloader.stakater.com/reload: "app-config" 처럼 지정.
      - 대안(툴 없이): Helm에서 pod template annotation에 설정의 sha256 체크섬을 넣어
                       설정이 바뀌면 template이 바뀌게(=재배포되게) 만드는 관용구도 흔하다.
EOF

echo
echo "다음: bash phase-06-config/scripts/02-secret-plaintext-etcd.sh"
