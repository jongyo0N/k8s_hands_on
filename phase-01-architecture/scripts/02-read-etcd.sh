#!/usr/bin/env bash
# Phase 1 / lab 2 — etcd를 직접 열어본다 (탐색 랩)
# 질문: apiserver가 etcd에 "무엇을" "어떤 포맷으로" 저장하나?
#       (kubectl은 JSON/YAML을 보여주지만, etcd 안의 실제 바이트는?)
# 실행: bash phase-01-architecture/scripts/02-read-etcd.sh
#
# 주의: -e 를 켜지 않는다. etcdctl 실행 경로를 환경에 맞춰 '탐지'하고,
#       바이너리를 head로 잘라 보느라 생기는 SIGPIPE 등을 '|| true'로 흡수한다.
set -uo pipefail

CLUSTER_NAME="k8s-mastery"
CTX="kind-${CLUSTER_NAME}"
CP="${CLUSTER_NAME}-control-plane"
CERT_DIR="/etc/kubernetes/pki/etcd"
ETCD_EP="https://127.0.0.1:2379"
DEMO_POD="etcd-demo"

# etcdctl 실행 방법 탐지:
#   (A) control-plane 노드 루트 FS에 etcdctl이 있으면 docker exec 로 직접 호출.
#   (B) 없으면(일반적) etcd 정적 Pod 컨테이너 안에는 etcdctl이 항상 있으니 crictl exec 로 호출.
# 두 경로 모두 ETCDCTL_API=3 + 동일 cert( /etc/kubernetes/pki/etcd/* )를 쓴다.
ETCD_CTR=""
if docker exec "${CP}" sh -c 'command -v etcdctl' >/dev/null 2>&1; then
  ETCD_MODE="node"
else
  ETCD_MODE="crictl"
  ETCD_CTR="$(docker exec "${CP}" crictl ps --name etcd --state Running -q 2>/dev/null | head -n1)"
fi

run_etcdctl() {  # $@ = etcdctl 서브커맨드/인자
  if [ "${ETCD_MODE}" = "node" ]; then
    docker exec "${CP}" env ETCDCTL_API=3 etcdctl \
      --endpoints="${ETCD_EP}" \
      --cacert="${CERT_DIR}/ca.crt" --cert="${CERT_DIR}/server.crt" --key="${CERT_DIR}/server.key" \
      "$@"
  else
    docker exec "${CP}" crictl exec "${ETCD_CTR}" env ETCDCTL_API=3 etcdctl \
      --endpoints="${ETCD_EP}" \
      --cacert="${CERT_DIR}/ca.crt" --cert="${CERT_DIR}/server.crt" --key="${CERT_DIR}/server.key" \
      "$@"
  fi
}

echo "==> 0) 전제 확인 + etcdctl 호출 경로 탐지"
if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
  echo "    클러스터 연결 불가. Phase 0 클러스터를 먼저 띄워라."
  exit 1
fi
echo "    etcdctl 실행 모드: ${ETCD_MODE}  ${ETCD_CTR:+(etcd 컨테이너 ${ETCD_CTR})}"

echo
echo "==> 1) etcd 상태 (raft 합의로 도는 KV 스토어 — 리더/term/DB크기)"
run_etcdctl endpoint status --write-out=table 2>/dev/null \
  || echo "    (endpoint status 실패 — cert 경로/컨테이너 이름을 확인하라)"

echo
echo "==> 2) 관찰용 Pod 하나를 만든다 (apply 되는 순간 etcd에 기록된다)"
kubectl --context "${CTX}" run "${DEMO_POD}" --image=nginx:1.27-alpine --restart=Never >/dev/null 2>&1 \
  && echo "    ${DEMO_POD} 생성" || echo "    (이미 존재 — 재사용)"
sleep 1

echo
echo "==> 3) etcd 키 공간 구조: 모든 오브젝트는 /registry/<리소스>/<네임스페이스>/<이름> 아래 산다"
TOTAL="$(run_etcdctl get /registry/ --prefix --keys-only 2>/dev/null | grep -c . )" || TOTAL="?"
echo "    /registry 아래 총 키 개수: ${TOTAL}"
echo "    샘플 키 몇 개:"
run_etcdctl get /registry/ --prefix --keys-only 2>/dev/null | grep -E '/registry/(pods|deployments|replicasets|services)/' | head -n 8 || true

echo
echo "==> 4) 저장된 값의 '실제 바이트'를 본다 — JSON이 아니라 바이너리(protobuf)다"
echo "    key: /registry/pods/default/${DEMO_POD}  (앞 512바이트를 od -c 로):"
run_etcdctl get "/registry/pods/default/${DEMO_POD}" --print-value-only 2>/dev/null \
  | head -c 512 | od -c | head -n 20 || true
cat <<'EOF'
    읽는 법:
      - 값은 "k8s\0" 매직 프리픽스로 시작한다 → apiserver가 쓰는 protobuf 저장 인코딩.
      - 그 뒤는 바이너리지만 중간중간 사람이 읽을 수 있는 문자열(필드명, 이미지명 등)이 섞여 보인다.
      - 즉 etcd는 "불투명한 바이트"만 저장한다. 어떤 스키마로 직렬화/역직렬화할지는 apiserver만 안다.
EOF

echo
echo "==> 5) 대조 — 똑같은 오브젝트를 apiserver는 사람이 읽는 JSON으로 '번역'해 준다"
kubectl --context "${CTX}" get pod "${DEMO_POD}" -o json 2>/dev/null \
  | grep -E '"(name|namespace|uid|resourceVersion|image|phase)":' | head -n 8 || true
cat <<'EOF'
    핵심 멘탈 모델:
      - etcd  = 강한 일관성(raft) KV 저장소. protobuf 바이트만 보관.
      - apiserver = etcd의 유일한 클라이언트 + 직렬화기 + 모든 정책의 관문.
        (그래서 etcd 디스크가 느려지면 → 쓰기/읽기/watch가 느려지고 → 컨트롤러 반응이 밀린다. 완료기준 Q2)
      - resourceVersion = etcd의 수정 리비전에서 온다 → watch 재개 지점이자 낙관적 동시성의 버전표. (완료기준 Q3)
EOF

echo
echo "==> 6) 정리 (관찰용 Pod 삭제 — 클러스터는 다음 Phase에서 계속 쓴다)"
kubectl --context "${CTX}" delete pod "${DEMO_POD}" --ignore-not-found >/dev/null 2>&1 \
  && echo "    ${DEMO_POD} 삭제" || true

echo
echo "다음: bash phase-01-architecture/scripts/03-stop-scheduler.sh"
