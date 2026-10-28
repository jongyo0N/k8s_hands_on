#!/usr/bin/env bash
# Phase 13 / preflight — 캡스톤 배포 전제 조건 점검
# 실행: bash phase-13-capstone/scripts/00-preflight.sh
#
# 캡스톤은 이전 Phase들의 산출물 위에 선다. 여기서 전제(클러스터·CRD·컨트롤러)를 확인한다.
# 필수(CRD)가 없으면 apply가 깨지므로 hard fail. 선택(metrics-server/CNI 집행)은 경고만.
set -euo pipefail

CTX="kind-k8s-mastery"
NS="capstone"
fail=0

echo "==> 1) 도구 점검"
for t in kubectl docker; do
  if command -v "$t" >/dev/null 2>&1; then echo "  [ok]   $t"; else echo "  [MISS] $t <- 필수"; fail=1; fi
done
if command -v kustomize >/dev/null 2>&1; then echo "  [ok]   kustomize"; else echo "  [--]   kustomize (없으면 'kubectl kustomize'로 대체)"; fi

echo
echo "==> 2) 클러스터 연결 (${CTX})"
if kubectl --context "${CTX}" get --raw='/readyz' >/dev/null 2>&1; then
  echo "  [ok] API server 응답"
else
  echo "  [MISS] ${CTX} API server 응답 없음. Phase 0의 01-create-cluster.sh로 클러스터를 먼저 만들 것."
  exit 1
fi

echo
echo "==> 3) 노드 Ready"
if kubectl --context "${CTX}" wait --for=condition=Ready nodes --all --timeout=30s >/dev/null 2>&1; then
  kubectl --context "${CTX}" get nodes -o wide
else
  echo "  [WARN] 일부 노드가 Ready가 아님:"; kubectl --context "${CTX}" get nodes || true
fi

echo
echo "==> 4) 필수 CRD (없으면 apply 실패)"
require_crd() {
  if kubectl --context "${CTX}" get crd "$1" >/dev/null 2>&1; then
    echo "  [ok]   $1"
  else
    echo "  [MISS] $1  <- $2"
    fail=1
  fi
}
require_crd gateways.gateway.networking.k8s.io  "Gateway API. Phase 4(phase-04-network-l7)에서 Gateway API CRD + 구현체를 설치."
require_crd httproutes.gateway.networking.k8s.io "Gateway API. 위와 동일."
require_crd servicemonitors.monitoring.coreos.com "Prometheus Operator. Phase 9(phase-09-observability)에서 kube-prometheus-stack 설치."

echo
echo "==> 5) 선택 전제 (경고만 — 없어도 apply는 되지만 기능 일부가 비활성)"
if kubectl --context "${CTX}" get deploy -n kube-system metrics-server >/dev/null 2>&1; then
  echo "  [ok]   metrics-server (HPA의 CPU/memory 메트릭 소스) — Phase 7"
else
  echo "  [WARN] metrics-server 없음 → HPA가 메트릭을 못 읽어 스케일 안 됨. Phase 7에서 설치."
fi
# kind 기본 CNI(kindnet)는 NetworkPolicy를 집행하지 않는다.
if kubectl --context "${CTX}" get daemonset -n kube-system -o name 2>/dev/null | grep -Eq 'cilium|calico'; then
  echo "  [ok]   NetworkPolicy 집행 가능 CNI(Cilium/Calico) 감지 — Phase 4"
else
  echo "  [WARN] Cilium/Calico 미감지. kind 기본 kindnet은 NetworkPolicy를 집행하지 않음 →"
  echo "         default-deny가 '존재'만 하고 트래픽은 흐른다. Phase 4에서 CNI 교체 필요."
fi

echo
echo "==> 6) 외부 네임스페이스 라벨 안내 (NetworkPolicy allow 매칭용)"
echo "   Gateway/monitoring 네임스페이스에 아래 라벨을 붙여야 allow 정책이 매칭된다:"
echo "     kubectl --context ${CTX} label ns <gateway-ns>    capstone.k8s/role=gateway    --overwrite"
echo "     kubectl --context ${CTX} label ns <monitoring-ns> capstone.k8s/role=monitoring --overwrite"

echo
if [ "${fail}" -ne 0 ]; then
  echo "결과: [FAIL] 필수 전제가 빠졌다. 위 [MISS] 항목을 먼저 해결할 것."
  exit 1
fi
echo "결과: [OK] 필수 전제 충족. 다음: bash phase-13-capstone/scripts/10-deploy.sh [dev|prod]"
