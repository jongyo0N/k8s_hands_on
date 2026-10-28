#!/usr/bin/env bash
# Phase 10 / lab 4 — 인증서 수명주기: 만료 확인 & 갱신
# kind에서 동작(control-plane 컨테이너 안 kubeadm 사용).
# 실행: bash scripts/04-cert-expiry.sh
set -uo pipefail

CP="k8s-mastery-control-plane"

echo "==> 1) 현재 인증서 만료 현황 (kubeadm)"
docker exec "$CP" kubeadm certs check-expiration 2>/dev/null \
  || echo "    kubeadm 미존재/권한 문제 — 노드 이미지/경로 확인"

cat <<'EOF'

    해석:
    - 기본 kubeadm 인증서 수명은 1년. 만료되면 apiserver/kubelet/컨트롤러 간
      mTLS 가 깨져 kubectl 자체가 먹통이 되는 '전면 장애'로 번진다.
    - 'CA' 는 10년이지만 leaf 인증서(apiserver, etcd, front-proxy 등)가 1년.

==> 2) 갱신 (연습 시)
    # 전체 갱신:
    #   docker exec k8s-mastery-control-plane kubeadm certs renew all
    # 갱신 후 control-plane 컴포넌트(static pod) 재기동이 필요할 수 있다:
    #   docker exec k8s-mastery-control-plane sh -c \
    #     'crictl ps --name kube-apiserver -q | xargs -r crictl stop'  (자동 재기동됨)
    # admin.conf 도 갱신되므로 kubeconfig 재발급 필요할 수 있음.

    [운영 교훈] 만료는 "조용히" 다가온다. 모니터링(만료 D-30 알림) + 자동 갱신(정기 재부팅/
    kubeadm upgrade 가 갱신을 겸함)을 걸어두는 것이 사고 예방의 핵심.
EOF
