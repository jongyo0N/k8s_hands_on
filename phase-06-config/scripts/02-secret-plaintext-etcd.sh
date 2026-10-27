#!/usr/bin/env bash
# Phase 6 / lab 2 — "Secret은 평문이다": etcd에서 '직접' 읽어 평문 저장임을 확인
# 실행: bash phase-06-config/scripts/02-secret-plaintext-etcd.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests/02-secret-encryption"
CTX="kind-k8s-mastery"
NS="phase-06"
CP="k8s-mastery-control-plane"   # Phase 0 kind 클러스터의 control-plane 컨테이너
K="kubectl --context ${CTX} -n ${NS}"

# etcdctl 실행 헬퍼.
#   - kind control-plane 노드 PATH에는 etcdctl이 없을 수 있다.
#   - 그래서 etcd 정적 Pod 컨테이너 안의 etcdctl을 crictl로 호출한다(etcd 이미지는 distroless라 sh 없이 직접 실행).
#   - ETCDCTL_API=3 은 etcd 3.4+ 기본값이라 별도 지정 불필요.
#   - (대안) kubectl -n kube-system exec etcd-${CP} -- etcdctl ...  로도 가능.
etcd_get() {
  local key="$1"
  if docker exec "${CP}" sh -c 'command -v etcdctl' >/dev/null 2>&1; then
    docker exec "${CP}" etcdctl \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key \
      get "${key}"
    return
  fi
  local eid
  eid="$(docker exec "${CP}" crictl ps --name etcd --state Running -q 2>/dev/null | head -1)"
  [ -n "${eid}" ] || { echo "    [에러] etcd 컨테이너를 못 찾음" >&2; return 1; }
  docker exec "${CP}" crictl exec "${eid}" etcdctl \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get "${key}"
}

echo "==> 0) 사전 점검: control-plane 컨테이너 ${CP}"
docker ps --filter "name=${CP}" --format '{{.Names}}' | grep -qx "${CP}" || {
  echo "    [에러] ${CP} 컨테이너가 없음. Phase 0 kind 클러스터가 떠 있는지 확인."
  exit 1
}

echo
echo "==> 1) 데모 Secret 생성 (stringData=평문으로 작성)"
$K apply -f "${MANIFESTS}/secret.yaml"

echo
echo "==> 2) kubectl로 보면 base64 — '인코딩'일 뿐이다"
printf "    .data.db-password (base64) = "; $K get secret demo-plain -o jsonpath='{.data.db-password}'; echo
printf "    base64 -d 하면 평문       = "; $K get secret demo-plain -o jsonpath='{.data.db-password}' | base64 -d; echo

echo
echo "==> 3) etcd에서 '직접' 읽는다 (control-plane 안에서 etcdctl → hexdump)"
echo "    key: /registry/secrets/${NS}/demo-plain"
etcd_get "/registry/secrets/${NS}/demo-plain" | hexdump -C | head -30

cat <<'EOF'

    해석:
      - 'k8s\x00' 접두어 뒤 protobuf 안에 db-password 값이 '사람이 읽는 평문'으로 보인다.
        (etcd엔 base64조차 아니라 '디코드된 원문 바이트'로 저장 — base64는 API 표현일 뿐.)
      - 즉 etcd 파일/스냅샷/백업/디스크에 접근 가능한 사람은 Secret을 그냥 읽는다.
      - "Secret은 안전한가?"는 계층을 나눠 답해야 한다:
          저장(at rest): etcd 암호화 / KMS   <-- 02b에서 직접 켠다
          전송(in transit): etcd client/peer TLS (kubeadm 기본 on)
          접근(access): RBAC로 get/list secrets 권한 제한
          노드(node): kubelet은 Secret을 tmpfs(메모리)로 올려 디스크 잔존 최소화
EOF

echo
echo "다음(선택·고급·파괴적): bash phase-06-config/scripts/02b-enable-encryption-at-rest.sh"
