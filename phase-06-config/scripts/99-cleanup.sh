#!/usr/bin/env bash
# Phase 6 — 정리. 네임스페이스 phase-06 및 (선택) 설치한 operator 제거.
# 실행: bash phase-06-config/scripts/99-cleanup.sh
#   operator까지 전부: WITH_OPERATORS=1 bash phase-06-config/scripts/99-cleanup.sh
set -uo pipefail

CTX="kind-k8s-mastery"
NS="phase-06"
K="kubectl --context ${CTX}"

echo "==> 1) 네임스페이스 ${NS} 삭제 (그 안의 ConfigMap/Secret/Deployment/ExternalSecret 등 포함)"
$K delete namespace "${NS}" --ignore-not-found

if [ "${WITH_OPERATORS:-0}" = "1" ]; then
  echo
  echo "==> 2) Reloader / ESO helm 릴리스 + 네임스페이스 삭제"
  helm uninstall reloader --kube-context "${CTX}" -n reloader 2>/dev/null || true
  $K delete namespace reloader --ignore-not-found
  helm uninstall external-secrets --kube-context "${CTX}" -n external-secrets 2>/dev/null || true
  $K delete namespace external-secrets --ignore-not-found
  echo "    (ESO CRD는 남을 수 있음: kubectl get crds | grep external-secrets 로 확인 후 수동 삭제)"
else
  echo
  echo "    (operator까지 지우려면: WITH_OPERATORS=1 bash phase-06-config/scripts/99-cleanup.sh)"
fi

cat <<EOF

⚠️ 02b(encryption at rest)를 실행했다면 이 스크립트로는 '되돌지 않는다'.
   kube-apiserver 매니페스트 변경은 02b 하단의 '롤백' 절차로 수동 복구하거나,
   Phase 0 scripts/99-cleanup.sh 로 클러스터 자체를 지우고 새로 만드는 것이 가장 깔끔하다.
EOF
