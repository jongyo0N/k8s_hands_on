#!/usr/bin/env bash
# Phase 12 / lab 3 — canary 배포 트리거 & 관찰 (관찰 랩)
# 질문: 이미지 한 줄을 바꾸면 canary 단계(setWeight/pause/analysis)가 어떻게 흐르나?
# 실행: bash phase-12-gitops/scripts/03b-canary-observe.sh
#
# 주의: -e를 켜지 않는다. 플러그인이 없을 수도, 분석이 일부러 실패할 수도 있는 관찰 랩이다.
set -uo pipefail

CTX="kind-k8s-mastery"
WL_NS="phase-12"
NEW_IMAGE="${NEW_IMAGE:-nginx:1.29-alpine}" # canary를 트리거할 새 이미지.

have_plugin() { kubectl --context "${CTX}" argo rollouts version >/dev/null 2>&1; }

show_status() {
  if have_plugin; then
    kubectl --context "${CTX}" argo rollouts get rollout web -n "${WL_NS}" || true
  else
    echo "    (kubectl-argo-rollouts 플러그인 없음 — 원시 상태로 대체)"
    kubectl --context "${CTX}" -n "${WL_NS}" get rollout/web \
      -o jsonpath='    phase={.status.phase}  step={.status.currentStepIndex}  message={.status.message}{"\n"}' 2>/dev/null || true
    kubectl --context "${CTX}" -n "${WL_NS}" get pods -l app=web-rollout -o wide 2>/dev/null || true
  fi
}

echo "==> 0) 현재 Rollout 상태"
kubectl --context "${CTX}" -n "${WL_NS}" get rollout/web >/dev/null 2>&1 \
  || { echo "    Rollout web 이 없음. 먼저 03-install-rollouts.sh 실행."; exit 0; }
show_status

echo
echo "==> 1) 이미지 업데이트로 canary 트리거 → ${NEW_IMAGE}"
if have_plugin; then
  kubectl --context "${CTX}" argo rollouts set image web web="${NEW_IMAGE}" -n "${WL_NS}" || true
else
  kubectl --context "${CTX}" -n "${WL_NS}" patch rollout/web --type merge \
    -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"web\",\"image\":\"${NEW_IMAGE}\"}]}}}}" || true
fi
sleep 5

echo
echo "==> 2) canary 1단계 관찰 — setWeight: 20 적용 후 pause:{}(무기한) 에서 멈춘다"
show_status
echo "    해석: 전체의 ~20%만 새 버전. 나머지는 stable. 사람이 승격할 때까지 대기(Paused)."

echo
echo "==> 3) 수동 승격 — pause를 넘어 다음 단계(setWeight 50 → 30초 → analysis)로"
if have_plugin; then
  kubectl --context "${CTX}" argo rollouts promote web -n "${WL_NS}" || true
else
  echo "    플러그인이 없으면 승격은 UI 또는 아래 패치로:"
  echo "      kubectl --context ${CTX} -n ${WL_NS} patch rollout/web --type merge -p '{\"status\":{\"pause\":null}}'  # (권장X, 플러그인 사용 권장)"
fi
sleep 5
show_status

cat <<'EOF'

==> 4) analysis 단계에서 무슨 일이 일어나나 (관측성 선행조건의 핵심)
    - Prometheus가 있고 success-rate >= 0.95  → 측정 통과 → 자동으로 100% 승격.
    - Prometheus가 없거나 쿼리 실패          → AnalysisRun Error/Inconclusive
                                               → Rollout abort → stable로 자동 롤백.
    => 자동 canary/롤백은 "신뢰할 수 있는 메트릭"이 전제. 메트릭이 부실하면
       자동화가 오히려 위험하다(가짜 통과/가짜 실패). 그래서 관측성이 먼저다.

수동 개입 명령 (플러그인 기준):
    kubectl --context kind-k8s-mastery argo rollouts get rollout web -n phase-12 --watch
    kubectl --context kind-k8s-mastery argo rollouts promote web -n phase-12   # 다음 단계로
    kubectl --context kind-k8s-mastery argo rollouts abort   web -n phase-12   # 즉시 롤백
    kubectl --context kind-k8s-mastery argo rollouts undo     web -n phase-12   # 이전 리비전으로

NOTES.md에 각 단계의 pod 비율/상태와 analysis 결과를 적는다.
다음: bash phase-12-gitops/scripts/04-applicationset.sh
EOF
