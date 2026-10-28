#!/usr/bin/env bash
# Phase 12 / lab 2 — drift & self-heal (관찰 랩)
# 질문: "git에 있는 것이 곧 클러스터 상태"는 언제 깨지고, Argo CD는 어떻게 되돌리나?
# 실행: bash phase-12-gitops/scripts/02-drift-selfheal.sh
#
# 주의: -e를 켜지 않는다. 중간에 상태를 바꿔가며 "관찰"하는 랩이라 일부 명령은 실패할 수 있다.
set -uo pipefail

CTX="kind-k8s-mastery"
NS="argocd"
APP="phase-12-web"
WL_NS="phase-12"

refresh_and_show() {
  # Argo CD가 git과 live를 다시 비교하도록 refresh를 요청하고 sync 상태를 출력.
  kubectl --context "${CTX}" -n "${NS}" annotate application/"${APP}" \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
  sleep 8
  local sync health
  sync="$(kubectl --context "${CTX}" -n "${NS}" get application/"${APP}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl --context "${CTX}" -n "${NS}" get application/"${APP}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  echo "    sync=${sync:-?}  health=${health:-?}  replicas(live)=$(kubectl --context "${CTX}" -n "${WL_NS}" get deploy/web -o jsonpath='{.spec.replicas}' 2>/dev/null || echo '?')"
}

echo "==> 0) 전제: lab 1의 phase-12-web 앱이 Synced 상태여야 한다."
kubectl --context "${CTX}" -n "${NS}" get application/"${APP}" >/dev/null 2>&1 \
  || { echo "    ${APP} 가 없음. 먼저 01b-bootstrap-app-of-apps.sh 를 실행한다."; exit 0; }
echo "    git 선언값(replicas): $(kubectl --context "${CTX}" -n "${WL_NS}" get deploy/web -o jsonpath='{.spec.replicas}' 2>/dev/null || echo '?')  (매니페스트상 2)"

echo
echo "==> 1) selfHeal을 OFF로 (automated.prune 유지, selfHeal만 false)"
kubectl --context "${CTX}" -n "${NS}" patch application/"${APP}" --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":false}}}}' || true

echo
echo "==> 2) 수동 drift 만들기: kubectl로 replicas를 5로 (git에는 없는 변경)"
kubectl --context "${CTX}" -n "${WL_NS}" scale deployment/web --replicas=5 || true

echo
echo "==> 3) selfHeal OFF 상태에서 관찰 — Argo는 drift를 '감지'하되 '교정'하지 않는다"
refresh_and_show
echo "    기대: sync=OutOfSync, 하지만 replicas는 5로 그대로. (감지 O, 자동 교정 X)"

echo
echo "==> 4) selfHeal을 ON으로"
kubectl --context "${CTX}" -n "${NS}" patch application/"${APP}" --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' || true

echo
echo "==> 5) selfHeal ON 상태에서 관찰 — Argo가 git 기준(2)으로 되돌린다"
refresh_and_show
echo "    (반영이 느리면 몇 초 뒤 아래로 재확인)"
sleep 10
refresh_and_show
echo "    기대: sync=Synced, replicas=2 로 자동 복구."

cat <<'EOF'

해석 / 정리:
  - drift = "클러스터 live 상태"가 "git 선언 상태"와 어긋난 것.
    주로 (a) 사람이 kubectl로 손댐 (b) 다른 컨트롤러/HPA가 바꿈 (c) 수동 핫픽스.
  - syncPolicy.automated 의 두 스위치:
      * selfHeal: live가 git과 달라지면 git 기준으로 되돌린다(이 랩의 주제).
      * prune   : git에서 리소스를 지우면 클러스터에서도 지운다(없으면 "고아" 리소스가 남음).
  - selfHeal=OFF 의 쓸모: 긴급 수동 개입(인시던트) 중에는 자동 되돌림이 방해가 될 수 있다.
    대신 drift를 "감지"는 계속 하므로, 끝나면 git을 고쳐 정상 경로로 되돌린다.
  - 결론: "git=클러스터"는 selfHeal이 지켜준다. 단, HPA처럼 의도적으로 live를 바꾸는
    컨트롤러가 있으면 해당 필드를 ignoreDifferences로 빼야 selfHeal과 싸우지 않는다.

NOTES.md에 sync/health/replicas 관찰값을 적는다.
다음: bash phase-12-gitops/scripts/03-install-rollouts.sh
EOF
