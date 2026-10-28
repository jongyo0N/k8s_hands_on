#!/usr/bin/env bash
# 캡스톤 장애주입 2 — CoreDNS 다운 → 이름해석 장애 → 복구
# 실행: bash scripts/fault-injection/02-dns-outage.sh
set -uo pipefail
CTX="kind-k8s-mastery"; NS="capstone"

echo "==> 사전: CoreDNS 현황 + 정상 이름해석"
kubectl --context "$CTX" -n kube-system get deploy coredns
ORIG=$(kubectl --context "$CTX" -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}')
echo "    현재 replicas=$ORIG"
kubectl --context "$CTX" -n "$NS" run dnstest --image=busybox:1.36 --restart=Never --rm -it --quiet -- \
  sh -c 'nslookup kubernetes.default.svc.cluster.local; echo "---(IP 직접은 DNS 없이도 됨)"' 2>/dev/null || true

echo
echo "==> 장애 주입: CoreDNS를 0으로 스케일"
kubectl --context "$CTX" -n kube-system scale deploy coredns --replicas=0
kubectl --context "$CTX" -n kube-system rollout status deploy/coredns --timeout=30s 2>/dev/null || true

echo "==> 관찰: 이제 이름해석 실패(타임아웃) — IP 직접 호출은 여전히 됨"
kubectl --context "$CTX" -n "$NS" run dnstest2 --image=busybox:1.36 --restart=Never --rm -it --quiet -- \
  sh -c 'nslookup kubernetes.default.svc.cluster.local' 2>/dev/null || echo "    <-- 예상대로 이름해석 실패"

echo
echo "==> 복구: CoreDNS 원복"
kubectl --context "$CTX" -n kube-system scale deploy coredns --replicas="${ORIG:-2}"
kubectl --context "$CTX" -n kube-system rollout status deploy/coredns --timeout=60s || true

cat <<'EOF'

교훈: '간헐적 서비스 호출 실패'의 흔한 범인이 DNS다. 체크 순서 —
  1) CoreDNS 떠 있나?  2) NetworkPolicy가 DNS egress(53)를 막았나?(Phase 4 함정)
  3) ndots로 불필요 질의가 폭증하나?(Phase 3)
RUNBOOK 2번 항목을 채워보라.
EOF
