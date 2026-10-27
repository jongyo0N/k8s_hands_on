#!/usr/bin/env bash
# Phase 6 / lab 4 — 같은 앱을 Helm과 Kustomize로 각각 렌더해 결과 비교
#   (클러스터 불필요 — 순수 렌더/빌드 비교. 실제 적용 예시는 맨 아래 주석 참고.)
# 실행: bash phase-06-config/scripts/04-helm-vs-kustomize.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="${SCRIPT_DIR}/../manifests/04-packaging"
HELM_CHART="${PKG}/helm/myapp"
KUST="${PKG}/kustomize"

command -v helm >/dev/null 2>&1 || { echo "[에러] helm 필요: brew install helm"; exit 1; }

# kustomize: 독립 바이너리 없으면 kubectl 내장('kubectl kustomize') 사용
if command -v kustomize >/dev/null 2>&1; then
  kbuild() { kustomize build "$1"; }
elif kubectl kustomize --help >/dev/null 2>&1; then
  kbuild() { kubectl kustomize "$1"; }
else
  echo "[에러] kustomize도 kubectl도 없음"; exit 1
fi

echo "########################################"
echo "# A. Helm — 템플릿 + values 주입"
echo "########################################"
echo "==> helm template myapp (base values)"
helm template myapp "${HELM_CHART}" | grep -E '^kind:|^  name:|  replicas:|  APP_ENV:|  GREETING:' || true
echo
echo "==> helm template myapp -f values-prod.yaml (prod 오버라이드)"
helm template myapp "${HELM_CHART}" -f "${HELM_CHART}/values-prod.yaml" | grep -E '  replicas:|  APP_ENV:|  GREETING:' || true

echo
echo "########################################"
echo "# B. Kustomize — base + overlay 패치"
echo "########################################"
echo "==> build overlays/dev"
kbuild "${KUST}/overlays/dev" | grep -E '^kind:|^  name:|^  namespace:|  replicas:|  APP_ENV:|  GREETING:' || true
echo
echo "==> build overlays/prod"
kbuild "${KUST}/overlays/prod" | grep -E '^kind:|^  name:|^  namespace:|  replicas:|  APP_ENV:|  GREETING:' || true

cat <<'EOF'

    비교 포인트 (NOTES.md에 소감 기록):
      - Helm: Go 템플릿 + values로 '주입'. 패키지 배포·버전·롤백(helm history/rollback)에 강함.
              대신 YAML이 바로 안 보여 helm template로 렌더를 확인하며 디버깅.
      - Kustomize: 템플릿 언어 없음. 순수 YAML base + 선언적 patch/transformer(namePrefix, labels, namespace).
              가독성·단순함이 강점. 복잡한 조건 분기/반복에는 표현력이 부족.
      - 관찰: 두 방식 모두 'base 1벌 + 환경 차이(replicas/APP_ENV/GREETING)'를 분리해 관리.
              Kustomize는 namePrefix(dev-/prod-)가 configMapRef 참조까지 자동으로 따라 고침(nameReference).
      - 실무 관용: 서드파티는 Helm(받아 쓰기), 자체 앱은 Kustomize. 또는 'helm template → kustomize 후처리'.
      - ⚠️ 공급망: Bitnami 공개 카탈로그 축소(2025) 사례처럼 '차트/이미지 출처·미러 전략'도 설계 대상.
EOF

echo
echo "    (선택) 실제 적용해 보려면:"
echo "      helm upgrade --install myapp-dev ${HELM_CHART} \\"
echo "        --kube-context kind-k8s-mastery -n phase-06 --create-namespace"
echo "      kubectl --context kind-k8s-mastery apply -k ${KUST}/overlays/dev"
echo
echo "완료. 소감과 완료기준 답을 phase-06-config/NOTES.md 에 기록할 것."
