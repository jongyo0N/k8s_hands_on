#!/usr/bin/env bash
# Phase 4 / lab 3 — default-deny NetworkPolicy → 통신 끊김 → 필요한 것만 허용
#                   (DNS egress를 '일부러' 빼서 이름 해석 실패를 관찰한 뒤 수정)
# 실행: bash phase-04-network-l7/scripts/03-netpol-default-deny.sh
# 전제: lab 01 완료(Cilium). NetworkPolicy 집행자는 CNI(Cilium)다.
#
# 주의: 관찰/실패유도 랩이라 -e 를 켜지 않는다. 중간에 '일부러 실패하는' 명령이 있다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests/netpol"
CLUSTER_NAME="k8s-l7"
CTX="kind-${CLUSTER_NAME}"
NS="netpol-demo"

cexec() { kubectl --context "${CTX}" -n "${NS}" exec deploy/netpol-client -- "$@"; }

probe() {
  printf "      nslookup(이름) : "
  if cexec timeout 6 nslookup netpol-server >/dev/null 2>&1; then echo "OK(해석됨)"; else echo "FAIL(해석실패)"; fi
  printf "      curl by 이름   : "
  out="$(cexec curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://netpol-server 2>/dev/null || true)"
  if [ -n "${out}" ] && [ "${out}" != "000" ]; then echo "HTTP ${out}"; else echo "실패/timeout"; fi
  printf "      curl by IP     : "
  out="$(cexec curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${SERVER_IP}" 2>/dev/null || true)"
  if [ -n "${out}" ] && [ "${out}" != "000" ]; then echo "HTTP ${out}"; else echo "실패/timeout"; fi
}

echo "==> 1) 네임스페이스 + 샘플 앱(server/client) 배포"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/00-namespace.yaml"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/01-sample-apps.yaml"
kubectl --context "${CTX}" -n "${NS}" rollout status deploy/netpol-server --timeout=120s || true
kubectl --context "${CTX}" -n "${NS}" rollout status deploy/netpol-client --timeout=120s || true
SERVER_IP="$(kubectl --context "${CTX}" -n "${NS}" get pod -l app=netpol-server \
  -o jsonpath='{.items[0].status.podIP}')"
echo "    server Pod IP = ${SERVER_IP}"

echo
echo "==> 2) [기준선] 정책 없음 → 전부 성공해야 정상"
probe

echo
echo "==> 3) default-deny(ingress+egress) 적용 → 전부 끊긴다"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/02-default-deny.yaml"
sleep 2
probe
echo "    해석: egress까지 막혀 DNS 질의 패킷조차 못 나간다. 셋 다 실패가 정상."

echo
echo "==> 4) '필요한 것만 허용' ... 인데 DNS를 깜빡함 (03-allow-app-no-dns)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/03-allow-app-no-dns.yaml"
sleep 2
probe
cat <<'EOF'
    해석(이 랩의 핵심):
      - 'curl by IP' 는 성공  → L3/L4 경로(client→server:80)는 열렸다.
      - 'nslookup/이름' 은 실패 → DNS(egress 53→kube-dns)를 안 열어 '이름 해석'만 깨졌다.
      - 즉 "앱은 허용했는데 왜 안 되지?"의 범인은 거의 항상 '빠진 DNS egress'다.
EOF

echo
echo "==> 5) DNS egress 허용으로 수정 (04-allow-dns)"
kubectl --context "${CTX}" apply -f "${MANIFESTS}/04-allow-dns.yaml"
sleep 2
probe
echo "    해석: 이름 해석 + 이름으로 curl 모두 성공. 지뢰 제거 완료."

cat <<EOF

관측 보너스 — Hubble로 '드롭된' 플로우를 눈으로:
  hubble observe --namespace ${NS} --verdict DROPPED --follow
  (3~4단계에서 policy-verdict DROPPED 가 찍힌다. 집행자가 Cilium임을 확인.)

완료 기준 질문 (NOTES.md):
  - NetworkPolicy는 '누가/어느 레이어에서' 집행하나? (답: CNI = Cilium eBPF, 명세≠집행)
  - default-deny egress에서 가장 먼저 열어야 하는 것은? (답: kube-dns 53/UDP+TCP)

다음: (선택) bash phase-04-network-l7/scripts/04-mtls.sh   |   정리: 99-cleanup.sh
EOF
