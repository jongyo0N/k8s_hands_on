#!/usr/bin/env bash
# Phase 0 / lab 2 — kubeconfig와 인증 체인 뜯어보기
# 실행: bash phase-00-setup/scripts/02-inspect-kubeconfig.sh
set -euo pipefail

CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
USER_NAME="kind-${CLUSTER_NAME}"

echo "==> 현재 컨텍스트"
kubectl config current-context

echo
echo "==> kubeconfig 구조 (clusters / users / contexts)"
echo "    - cluster: API server 주소 + 신뢰할 CA (서버를 '검증'하는 쪽)"
echo "    - user:    나를 '증명'하는 자격증명 (아래에서 확인)"
echo "    - context: (cluster + user + namespace) 묶음"
kubectl config view --minify

echo
echo "==> 나는 어떻게 인증되는가? kind는 클라이언트 인증서(client cert)를 kubeconfig에 심는다."
echo "    인증서의 Subject를 디코드:"
kubectl config view --raw \
  -o "jsonpath={.users[?(@.name=='${USER_NAME}')].user.client-certificate-data}" \
  | openssl base64 -d -A \
  | openssl x509 -noout -subject -issuer -startdate -enddate

cat <<'EOF'

    해석 포인트:
      - Subject의 'CN=' 값이 RBAC가 보는 "사용자(user)" 이름.
      - Subject의 'O='  값이 RBAC가 보는 "그룹(group)".
      - kind/kubeadm의 admin 자격증명은 cluster-admin에 (직접 또는 그룹을 통해) 묶여 있다.
        → 그래서 지금 당신은 사실상 무엇이든 할 수 있다. (Phase 8에서 이 권한을 쪼갠다.)

    kubeconfig의 user 인증 방식은 크게 3가지다 — NOTES.md에서 각각을 설명해보라:
      1) client certificate  (지금 kind가 쓰는 방식)
      2) bearer token         (ServiceAccount 토큰 등)
      3) exec plugin          (예: aws eks get-token / gke-gcloud-auth-plugin — 클라우드에서 흔함)
EOF

echo
echo "==> 참고: 지금 내 권한을 직접 물어보기"
echo "    kubectl auth can-i '*' '*' --all-namespaces  ->  $(kubectl --context "${CTX}" auth can-i '*' '*' --all-namespaces 2>/dev/null)"

echo
echo "다음: bash phase-00-setup/scripts/03-controlplane-failure.sh"
