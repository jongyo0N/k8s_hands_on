#!/usr/bin/env bash
# Phase 12 / lab 1 — app-of-apps 부트스트랩
# 실행: bash phase-12-gitops/scripts/01b-bootstrap-app-of-apps.sh
#
# 사람이 apply하는 Application은 "루트" 하나뿐이다. 루트가 git에서 자식 Application을
# 읽어 apply하고, 자식이 다시 워크로드를 동기화한다.
# ★ 먼저 할 일: root-app.yaml / phase-12-web.yaml의 repoURL이 "본인 레포"인지 확인!
#   (기본값은 jongyo0N/k8s_hands_on. 포크했다면 README의 'GitOps 레포 설정'대로 바꾼다.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="argocd"
ROOT_APP="${SCRIPT_DIR}/../manifests/01-app-of-apps/root-app.yaml"

echo "==> 루트 Application 적용 (app-of-apps)"
grep -E '^\s+repoURL:' "${ROOT_APP}" | sed 's/^/    현재 repoURL: /'
kubectl --context "${CTX}" apply -f "${ROOT_APP}"

echo
echo "==> 루트가 자식을 만들고 동기화할 때까지 잠깐 대기"
kubectl --context "${CTX}" -n "${NS}" wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/root --timeout=180s || echo "    (아직 Synced 전 — git 접근/네트워크를 확인하고 아래 상태를 본다)"

echo
echo "==> Application 목록 (루트 + 자식)"
kubectl --context "${CTX}" -n "${NS}" get applications

echo
echo "==> 자식이 배포한 워크로드 (phase-12 네임스페이스)"
kubectl --context "${CTX}" -n phase-12 get deploy,svc,pods 2>/dev/null \
  || echo "    (아직 생성 전일 수 있음 — 수십 초 후 다시 확인)"

cat <<EOF

해석:
  - root → phase-12-web 로 이어지는 "앱의 앱" 트리가 git 한 곳에서 선언된다.
  - 앞으로 워크로드를 추가하려면: manifests/01-app-of-apps/apps/ 에 자식 Application을
    하나 더 커밋 → 루트가 알아서 집어서 배포한다(클러스터에 kubectl 직접 X).

다음: bash phase-12-gitops/scripts/02-drift-selfheal.sh
EOF
