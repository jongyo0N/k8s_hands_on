#!/usr/bin/env bash
# Phase 4 / lab 4 (선택) — "메시 없이 암호화/인증만": Cilium WireGuard 투명 암호화
# 실행: bash phase-04-network-l7/scripts/04-mtls.sh
# 전제: lab 01 완료(Cilium 설치됨).
# 옵션: CILIUM_VERSION=1.20.4 bash .../04-mtls.sh
#
# 이 랩의 의도: "메시가 준 것 vs 가져간 것"을 체감한다.
#   - mTLS/암호화만 필요하면 메시 없이 Cilium WireGuard(노드 간 트래픽 암호화)로 충분할 때가 많다.
#   - 더 나아가 '신원 기반 상호 인증'은 Cilium mutual auth(SPIFFE), 또는 Istio ambient로.
# Ref: https://docs.cilium.io/en/stable/security/network/encryption-wireguard/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="k8s-l7"
CTX="kind-${CLUSTER_NAME}"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"   # 최신: https://github.com/cilium/cilium/releases

echo "==> 1) Cilium WireGuard 투명 암호화 켜기 (helm upgrade + 재기동)"
helm upgrade cilium cilium/cilium --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard
kubectl --context "${CTX}" -n kube-system rollout restart ds/cilium
kubectl --context "${CTX}" -n kube-system rollout status ds/cilium --timeout=180s

echo
echo "==> 2) 암호화 상태 확인 (Encryption: Wireguard 가 보여야 함)"
echo "    cilium CLI가 있으면:  cilium status | grep -i Encryption"
kubectl --context "${CTX}" -n kube-system exec ds/cilium -- cilium-dbg status \
  | grep -i -A2 'Encryption' || true
echo
echo "    노드 간 WireGuard 피어 수 확인:"
kubectl --context "${CTX}" -n kube-system exec ds/cilium -- \
  cilium-dbg encrypt status 2>/dev/null || echo "    (cilium-dbg encrypt status 미지원 버전일 수 있음)"

cat <<'EOF'

==> 3) 한 발 더 — '신원 기반 상호 인증'이 필요하면 (매니페스트만 제공, 선택)
    (A) Cilium mutual authentication (SPIFFE/SPIRE):
        helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
          --set authentication.mutual.spire.enabled=true \
          --set authentication.mutual.spire.install.enabled=true
        kubectl apply -f phase-04-network-l7/manifests/mtls/cilium-mutual-auth.yaml
    (B) Istio ambient (사이드카 없는 메시):
        istioctl install --set profile=ambient -y
        kubectl label namespace netpol-demo istio.io/dataplane-mode=ambient
        kubectl apply -f phase-04-network-l7/manifests/mtls/istio-ambient-peerauth.yaml

==> 4) 기록할 것 (NOTES.md) — "메시가 준 것 vs 가져간 것"
    준 것:   자동 mTLS, 트래픽 분할/재시도/타임아웃, 일관된 텔레메트리
    가져간 것: 운영 복잡도, 리소스 오버헤드, 업그레이드 리스크
    → WireGuard만으로 끝낼 수 있는 조직이 많다. "메시 없이 버티기"가 정답일 때의 근거 3개를 적어보라.

정리: bash phase-04-network-l7/scripts/99-cleanup.sh
EOF
