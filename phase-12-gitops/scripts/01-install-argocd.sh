#!/usr/bin/env bash
# Phase 12 / lab 1 — Argo CD 설치 (버전 핀)
# 실행: bash phase-12-gitops/scripts/01-install-argocd.sh
# 옵션: ARGOCD_VERSION=v3.5.6 bash .../01-install-argocd.sh  (버전 고정)
set -euo pipefail

CTX="kind-k8s-mastery"
NS="argocd"
# 버전 핀. 최신 확인: https://github.com/argoproj/argo-cd/releases  (작성 시점 기준 v3.5.6)
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.6}"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Argo CD ${ARGOCD_VERSION} 설치 (네임스페이스 ${NS})"
echo "    매니페스트: ${INSTALL_URL}"
kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f -
kubectl --context "${CTX}" apply -n "${NS}" -f "${INSTALL_URL}"

echo
echo "==> 핵심 컴포넌트가 Ready 될 때까지 대기 (최초 이미지 pull로 수 분 걸릴 수 있음)"
# application-controller는 StatefulSet, 나머지는 Deployment.
kubectl --context "${CTX}" -n "${NS}" rollout status statefulset/argocd-application-controller --timeout=300s
for d in argocd-server argocd-repo-server argocd-applicationset-controller argocd-redis argocd-dex-server; do
  kubectl --context "${CTX}" -n "${NS}" rollout status "deployment/${d}" --timeout=300s
done

echo
echo "==> 초기 admin 비밀번호 (argocd-initial-admin-secret)"
PW="$(kubectl --context "${CTX}" -n "${NS}" get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
if [ -n "${PW}" ]; then
  echo "    user: admin"
  echo "    pass: ${PW}"
else
  echo "    (시크릿을 못 읽음 — 이미 비밀번호를 바꿨거나 시크릿이 삭제됨)"
fi

cat <<EOF

==> UI/CLI 접속 방법
    1) 포트포워드(별도 터미널에서 계속 실행):
         kubectl --context ${CTX} -n ${NS} port-forward svc/argocd-server 8080:443
    2) 브라우저: https://localhost:8080  (self-signed 인증서 경고는 무시)
    3) CLI 로그인(선택, argocd 설치 시):
         argocd login localhost:8080 --username admin --password '<위 비밀번호>' --insecure

다음: bash phase-12-gitops/scripts/01b-bootstrap-app-of-apps.sh
EOF
