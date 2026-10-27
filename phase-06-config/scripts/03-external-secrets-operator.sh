#!/usr/bin/env bash
# Phase 6 / lab 3 — External Secrets Operator: 외부(fake) 저장소 → k8s Secret 동기화 + 회전
#   ESO를 helm으로 설치(버전 핀)하고, fake provider SecretStore + ExternalSecret로
#   "외부 저장소가 진실의 원천"인 동기화/회전 흐름을 체험한다.
# 실행: bash phase-06-config/scripts/03-external-secrets-operator.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests/03-eso"
CTX="kind-k8s-mastery"
NS="phase-06"
K="kubectl --context ${CTX} -n ${NS}"
KE="kubectl --context ${CTX} -n external-secrets"

# 버전 핀. 최신 확인: helm repo add external-secrets https://charts.external-secrets.io && \
#                     helm repo update && helm search repo external-secrets/external-secrets --versions | head
ESO_CHART_VERSION="2.14.0"   # chart/app v2.14.0 (2025-10 기준). ESO v2.x는 external-secrets.io/v1 API 사용.

command -v helm >/dev/null 2>&1 || { echo "[에러] helm 필요: brew install helm"; exit 1; }

apply_retry() {  # ESO 웹훅이 준비될 때까지 apply 재시도
  local f="$1" n=0
  until $K apply -f "$f"; do
    n=$((n + 1)); [ "$n" -ge 12 ] && { echo "[에러] apply 실패: $f"; return 1; }
    echo "    (ESO 웹훅 준비 대기, 재시도 ${n})"; sleep 5
  done
}

echo "==> 1) external-secrets helm repo 추가/갱신"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null

echo
echo "==> 2) ESO 설치 (namespace external-secrets, chart ${ESO_CHART_VERSION}, CRD 포함)"
helm upgrade --install external-secrets external-secrets/external-secrets \
  --kube-context "${CTX}" \
  --namespace external-secrets --create-namespace \
  --version "${ESO_CHART_VERSION}" \
  --set installCRDs=true \
  --wait --timeout 300s

echo
echo "==> 3) 컨트롤러/웹훅/cert-controller 준비 대기"
for d in external-secrets external-secrets-webhook external-secrets-cert-controller; do
  $KE rollout status "deployment/${d}" --timeout=180s || true
done

echo
echo "==> 4) SecretStore(fake) + ExternalSecret 적용"
apply_retry "${MANIFESTS}/secretstore-fake.yaml"
apply_retry "${MANIFESTS}/externalsecret.yaml"

echo
echo "==> 5) ESO가 대상 Secret(demo-synced-secret)을 만들 때까지 대기"
for _ in $(seq 1 30); do
  $K get secret demo-synced-secret >/dev/null 2>&1 && break
  sleep 2
done
$K get externalsecret demo-externalsecret
printf "    동기화된 db-password = "
$K get secret demo-synced-secret -o jsonpath='{.data.db-password}' | base64 -d; echo

echo
echo "==> 6) 회전(rotation) 시연: fake provider 값 변경 → refreshInterval 뒤 Secret 자동 갱신"
$K apply -f - <<'EOF'
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: fake-store
  namespace: phase-06
spec:
  provider:
    fake:
      data:
        - key: "/demo/db/password"
          value: "s3cr3t-ROTATED-v2"
          version: "v2"
        - key: "/demo/api/token"
          value: "tok_fake_v2"
          version: "v2"
EOF
echo "    (externalsecret.yaml의 refreshInterval=15s 기준, 갱신까지 폴링)"
for i in $(seq 1 24); do
  val="$($K get secret demo-synced-secret -o jsonpath='{.data.db-password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  echo "    [t=$((i * 5))s] db-password=${val}"
  if [ "${val}" = "s3cr3t-ROTATED-v2" ]; then
    echo "    -> 회전 반영됨! 외부 저장소 값이 바뀌니 k8s Secret도 따라 갱신된다."
    break
  fi
  sleep 5
done

cat <<'EOF'

    해석 / 회전(rotation) 개념:
      - ExternalSecret = '의도'(어느 store의 어느 key를 어느 Secret으로 가져올지). 진실의 원천은 '외부 저장소'.
      - ESO 컨트롤러가 refreshInterval 주기로 store를 재조회 → 대상 Secret을 갱신(= 회전 전파).
      - 실무 회전 경로: 외부(Vault/AWS SM/GCP SM)에서 비밀 회전 → ESO가 새 값을 동기화 →
          · env로 주입한 Pod는 재시작해야 반영(Reloader와 조합, lab 1 참고)
          · volume/CSI로 마운트하면 파일이 자동 갱신(단, 앱이 reload 해야 함)
      - fake provider는 외부 시스템 없이 흐름만 체험하기 위한 것. 실제론 provider 블록만 교체하면 된다.
      - ⚖️ 비밀관리 4종 비교(트레이드오프)는 README / NOTES.md 참고(Sealed Secrets / ESO / Vault / SOPS).
EOF

echo
echo "다음: bash phase-06-config/scripts/04-helm-vs-kustomize.sh"
