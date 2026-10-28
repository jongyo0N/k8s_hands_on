#!/usr/bin/env bash
# Phase 8 / lab 5 — etcd 암호화(at rest) + audit 정책 (방어)
# ⚠️ 이 랩은 kube-apiserver static pod 를 수정한다. 실습 클러스터(kind)에서만 할 것.
# 실행: bash scripts/05-etcd-audit.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="kind-k8s-mastery"
NS="phase-08"
CP="k8s-mastery-control-plane"
ENC="${SCRIPT_DIR}/../manifests/05-etcd-audit/encryption-config.yaml"
AUDIT="${SCRIPT_DIR}/../manifests/05-etcd-audit/audit-policy.yaml"

echo "==> 0) 먼저: 암호화 '전' Secret 이 etcd 에 평문인지 확인"
kubectl --context "$CTX" -n "$NS" create secret generic demo-sec \
  --from-literal=token=s3cr3t --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - 2>/dev/null || true
echo "    etcd 직접 읽기(평문 base64 가 보이면 암호화 전):"
docker exec "$CP" sh -c \
  'ETCDCTL_API=3 etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt \
   --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
   get /registry/secrets/'"$NS"'/demo-sec | strings | head' 2>/dev/null \
  || echo "    (etcdctl 경로/인증서 환경에 맞게 조정 필요)"

cat <<EOF

==> 1) encryption at rest 적용 절차 (수동)
    a) 암호화 설정을 control-plane 에 복사:
       docker cp "${ENC}" ${CP}:/etc/kubernetes/enc/encryption-config.yaml
    b) /etc/kubernetes/manifests/kube-apiserver.yaml 에 추가:
       - command 에  --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
       - enc 디렉토리를 hostPath volume 으로 마운트
       (static pod 이라 저장하면 apiserver 가 자동 재기동)
    c) 기존 Secret 재암호화(새 키로 다시 써야 적용):
       kubectl --context ${CTX} get secrets -A -o json | kubectl --context ${CTX} replace -f -
    d) 다시 etcd 를 읽으면 'k8s:enc:...' 암호문이 보인다.

==> 2) audit 정책 적용 절차
    a) docker cp "${AUDIT}" ${CP}:/etc/kubernetes/audit/audit-policy.yaml
    b) kube-apiserver.yaml 에 --audit-policy-file / --audit-log-path 추가 + hostPath 마운트
    c) 민감 리소스(secrets 등) 접근이 audit 로그에 남는지 확인:
       docker exec ${CP} tail -n 20 /var/log/kubernetes/audit.log

    [트레이드오프] audit 레벨이 높을수록 가시성↑ 이지만 로그량·디스크·성능 비용↑.
    민감 리소스는 Metadata/Request 레벨, 나머지는 None 으로 선별하는 게 실무.
EOF

echo
echo "정리: kubectl --context ${CTX} -n ${NS} delete secret demo-sec --ignore-not-found"
