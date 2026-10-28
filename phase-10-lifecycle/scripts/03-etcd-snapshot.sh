#!/usr/bin/env bash
# Phase 10 / lab 3 — etcd snapshot 백업 & 복구
# kind에서 동작(control-plane 컨테이너 안 etcdctl 사용).
# 실행: bash scripts/03-etcd-snapshot.sh
set -uo pipefail

CTX="kind-k8s-mastery"
CP="k8s-mastery-control-plane"
PKI="/etc/kubernetes/pki/etcd"
EP="https://127.0.0.1:2379"
etcd() { docker exec "$CP" sh -c "ETCDCTL_API=3 etcdctl --endpoints=$EP --cacert=$PKI/ca.crt --cert=$PKI/server.crt --key=$PKI/server.key $*"; }

echo "==> 0) etcd 멤버/상태 확인"
etcd "member list -w table" || { echo "    etcd 접근 실패 — 경로/인증서 확인"; exit 0; }

echo
echo "==> 1) 테스트 리소스 생성 (나중에 '손실'시킬 대상)"
kubectl --context "$CTX" create ns snap-demo 2>/dev/null || true
kubectl --context "$CTX" -n snap-demo create configmap canary --from-literal=k=v 2>/dev/null || true

echo
echo "==> 2) snapshot 저장"
etcd "snapshot save /var/lib/etcd-snapshot.db" || true
echo "    호스트로 복사:"
docker cp "$CP":/var/lib/etcd-snapshot.db ./etcd-snapshot.db 2>/dev/null \
  && echo "    ./etcd-snapshot.db ($(du -h ./etcd-snapshot.db 2>/dev/null | cut -f1))" \
  || echo "    복사 실패(계속 진행 가능)"
etcd "snapshot status /var/lib/etcd-snapshot.db -w table" || true

cat <<EOF

==> 3) 복구(restore) — 개념과 주의
    restore 는 '스냅샷을 새 데이터 디렉토리로 풀고 etcd 를 그 디렉토리로 재기동'하는 작업이다:
      etcdctl snapshot restore /var/lib/etcd-snapshot.db --data-dir /var/lib/etcd-restored
      그 뒤 /etc/kubernetes/manifests/etcd.yaml 의 hostPath 를 복구 디렉토리로 교체 → etcd 재기동.
    ⚠️ kind single control-plane 에서 실제 restore 는 클러스터를 멈출 수 있으니
       학습용으로는 'save + status'까지만 하고, restore 는 폐기해도 되는 클러스터에서 연습한다.

    [경계] 이 스냅샷은 '클러스터 오브젝트'만 담는다. PV 안 데이터는 별도 백업 대상이다(Phase 5).
EOF

echo
echo "정리: kubectl --context $CTX delete ns snap-demo --ignore-not-found; rm -f ./etcd-snapshot.db"
