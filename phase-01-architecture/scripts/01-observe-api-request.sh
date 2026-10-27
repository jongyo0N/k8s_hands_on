#!/usr/bin/env bash
# Phase 1 / lab 1 — API 요청을 직접 관찰 (탐색 랩)
# 질문: 'kubectl get pods' 한 줄이 실제로는 어떤 HTTP 요청이고,
#       그 요청이 서버에서 인증 → 인가 → admission → etcd 로 어떻게 흐르나?
# 실행: bash phase-01-architecture/scripts/01-observe-api-request.sh
#
# 주의: -e 를 켜지 않는다. 백그라운드로 kubectl proxy를 띄웠다 죽이고(EXIT trap),
#       환경에 따라 실패할 수 있는 탐색 명령(curl, grep)에 '|| true'를 붙인다.
set -uo pipefail

CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
CP="${CLUSTER_NAME}-control-plane"
PROXY_PORT="18001"

echo "==> 0) 전제: Phase 0의 kind 클러스터가 떠 있어야 한다 (context ${CTX})."
if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
  echo "    클러스터에 연결 불가. Phase 0의 01-create-cluster.sh 를 먼저 실행하라."
  exit 1
fi
kubectl --context "${CTX}" cluster-info 2>/dev/null | head -n 2 || true

echo
echo "==> 1) 'API는 그냥 REST 서버다' — 루트 디스커버리를 직접 받아본다"
echo "    GET /api        (레거시 core 그룹의 버전 목록):"
kubectl --context "${CTX}" get --raw /api | head -c 300 || true
echo
echo
echo "    GET /apis       (named API 그룹 목록, 일부만):"
kubectl --context "${CTX}" get --raw /apis \
  | tr ',' '\n' | grep -E '"name"|"groupVersion"' | head -n 12 || true
echo
echo "    GET /api/v1     (core/v1 가 제공하는 리소스 종류 — pods/services/...):"
kubectl --context "${CTX}" get --raw /api/v1 \
  | tr ',' '\n' | grep -E '"name":"(pods|services|configmaps|nodes|endpoints)"' | head -n 8 || true

echo
echo "==> 2) 같은 요청을 -v=9 로 — 클라이언트가 실제로 날리는 HTTP를 본다"
echo "    (round_trippers 로그: curl 재현 명령 + 요청/응답 헤더 + 상태코드 + 왕복시간)"
kubectl --context "${CTX}" -v=9 get pods -n kube-system 2>&1 \
  | grep -E 'round_trippers' \
  | sed -E 's/^I[0-9]+ [0-9:.]+ +[0-9]+ //' \
  | head -n 16 || true
cat <<'EOF'
    읽는 법:
      - "curl -v -XGET ... 'https://127.0.0.1:PORT/api/v1/.../pods?limit=500'"
          → kubectl이 보낸 바로 그 요청. 서버 식별은 kubeconfig의 CA로, 나의 식별은
            클라이언트 인증서(TLS)로 한다 (Phase 0 lab 2에서 디코드한 그 cert).
      - "GET https://... 200 OK in NN milliseconds"
          → 왕복 한 번 + 소요시간. etcd가 느려지면 이 숫자가 커진다(lab 2/완료기준 Q2).
      - 응답 리스트에는 metadata.resourceVersion 이 들어온다 → watch/낙관적 동시성의 핵심(완료기준 Q3).
EOF

echo
echo "==> 3) 서버 쪽 파이프라인은 어디에 '설정'돼 있나 — apiserver 정적 Pod 매니페스트를 본다"
echo "    (kind는 control-plane 노드가 Docker 컨테이너라 docker exec 로 들여다본다)"
docker exec "${CP}" grep -E \
  -- '--authorization-mode|--enable-admission-plugins|--client-ca-file|--service-account-key-file|--enable-bootstrap-token-auth|--anonymous-auth|--etcd-servers' \
  /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null \
  | sed -E 's/^ *- */      /' || echo "    (매니페스트를 못 읽음 — control-plane 컨테이너 이름을 확인하라)"
cat <<'EOF'
    해석(모든 요청이 이 순서로 통과한다):
      1. 인증(authN)   : --client-ca-file / --service-account-key-file / --enable-bootstrap-token-auth
                         → "너 누구냐"를 client cert·token 등으로 확인. 실패하면 401.
      2. 인가(authZ)   : --authorization-mode=Node,RBAC
                         → "그걸 할 권한 있냐"를 RBAC(+Node)로 판정. 실패하면 403.
      3. admission     : --enable-admission-plugins=...  (mutating → validating 순)
                         → 기본값 주입/정책 검증(예: 리소스쿼터, 네임스페이스 존재 등).
      4. 저장          : --etcd-servers=...  로 etcd에 최종 기록 (다음 lab에서 직접 열어본다).
    즉 apiserver는 etcd에 접근하는 유일한 컴포넌트이자 모든 정책의 단일 관문이다.
EOF

echo
echo "==> 4) kubectl proxy 로 API를 브라우징 (로컬 ${PROXY_PORT} 포트가 인증을 대신 처리)"
kubectl --context "${CTX}" proxy --port="${PROXY_PORT}" >/dev/null 2>&1 &
PROXY_PID=$!
trap 'kill "${PROXY_PID}" 2>/dev/null || true' EXIT
sleep 2
echo "    GET /version (서버 빌드 정보):"
curl -s "http://127.0.0.1:${PROXY_PORT}/version" || echo "    (proxy 연결 실패 — ${PROXY_PORT} 포트 사용 중일 수 있음)"
echo
echo "    GET /api/v1/namespaces/default/pods (default 네임스페이스 Pod 목록, 앞부분만):"
curl -s "http://127.0.0.1:${PROXY_PORT}/api/v1/namespaces/default/pods" | head -c 300 || true
echo
echo "    팁: 브라우저로 http://127.0.0.1:${PROXY_PORT}/openapi/v2 를 열면 전체 API 스키마를 볼 수 있다."
echo "        (이 스크립트가 끝나면 proxy는 자동 종료된다.)"

echo
echo "다음: bash phase-01-architecture/scripts/02-read-etcd.sh"
