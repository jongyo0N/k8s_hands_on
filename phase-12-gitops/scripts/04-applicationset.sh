#!/usr/bin/env bash
# Phase 12 / lab 4 — ApplicationSet로 dev/stg/prod 전개
# 실행: bash phase-12-gitops/scripts/04-applicationset.sh
# 옵션: GEN=git bash .../04-applicationset.sh   (git generator 버전으로 적용. 기본은 list)
#
# ★ 먼저 할 일: applicationset-*.yaml 의 repoURL이 "본인 레포"인지 확인!
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="argocd"
GEN="${GEN:-list}" # list | git
APPSET="${SCRIPT_DIR}/../manifests/04-applicationset/applicationset-${GEN}.yaml"

[ -f "${APPSET}" ] || { echo "GEN=${GEN} 에 해당하는 파일이 없다: ${APPSET}"; exit 1; }

echo "==> (선택) 오버레이 로컬 렌더 미리보기 — replicas가 환경별로 다른지 확인"
for env in dev stg prod; do
  echo "    --- ${env} ---"
  kubectl --context "${CTX}" kustomize "${SCRIPT_DIR}/../manifests/04-applicationset/envs/${env}" 2>/dev/null \
    | grep -E 'kind:|replicas:|name:' | head -n 6 || echo "      (kustomize 렌더 생략)"
done

echo
echo "==> ApplicationSet 적용 (generator=${GEN})"
grep -E '^\s+repoURL:' "${APPSET}" | head -n1 | sed 's/^/    repoURL: /'
kubectl --context "${CTX}" apply -f "${APPSET}"

echo
echo "==> ApplicationSet이 만들어낸 Application들 (web-dev / web-stg / web-prod)"
sleep 8
kubectl --context "${CTX}" -n "${NS}" get applicationset web-envs 2>/dev/null || true
kubectl --context "${CTX}" -n "${NS}" get applications -l '!argocd.argoproj.io/application-set-name' 2>/dev/null >/dev/null || true
kubectl --context "${CTX}" -n "${NS}" get applications 2>/dev/null | grep -E 'NAME|web-' || true

echo
echo "==> 각 환경 네임스페이스의 replicas 확인 (dev=1 / stg=2 / prod=3 로 '파라미터만' 다름)"
for env in dev stg prod; do
  r="$(kubectl --context "${CTX}" -n "phase-12-${env}" get deploy/web -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  echo "    phase-12-${env}: replicas=${r:-(아직 동기화 전)}"
done

cat <<EOF

해석:
  - ApplicationSet 1개가 dev/stg/prod Application 3개를 "찍어냈다". template은 공유하고
    환경별로 바뀌는 건 오버레이 경로(=replicas 등 파라미터)뿐이다.
  - list generator: 환경 목록을 YAML에 직접 나열(간단, 명시적).
    git generator : envs/ 디렉토리 구조가 진실의 원천(환경 추가 = 디렉토리 추가).
    (GEN=git bash phase-12-gitops/scripts/04-applicationset.sh 로 대안 버전 적용)
  - promotion 흐름: 보통 dev→stg→prod 순으로 "같은 커밋/이미지 태그"를 승격한다.
    디렉토리 per 환경이면 PR로 변경 추적이 쉽다(브랜치 per 환경 대비 장점).

정리: bash phase-12-gitops/scripts/99-cleanup.sh
EOF
