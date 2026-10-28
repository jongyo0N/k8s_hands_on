#!/usr/bin/env bash
# Phase 6 / lab 1 — ConfigMap 주입: env vs volume 전파 차이 관찰
#   같은 ConfigMap을 env(valueFrom)와 volume mount 두 방식으로 '동시에' 주입한 뒤,
#   ConfigMap을 수정해 (env=반영 안 됨 / volume=일정 시간 뒤 파일 갱신) 차이를 본다.
# 실행: bash phase-06-config/scripts/01-configmap-env-vs-volume.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/../manifests/01-config"
CTX="kind-k8s-mastery"
NS="phase-06"
K="kubectl --context ${CTX} -n ${NS}"

echo "==> 1) ConfigMap + Deployment(동일 CM을 env/volume 둘 다로 주입) 적용"
$K apply -f "${MANIFESTS}/configmap.yaml"
$K apply -f "${MANIFESTS}/deployment.yaml"
$K rollout status deployment/config-demo --timeout=120s

echo
echo "==> 2) 현재 값 확인 (env와 file이 둘 다 v1이어야 정상)"
sleep 6
$K logs deploy/config-demo --tail=2

echo
echo "==> 3) ConfigMap을 v2로 수정 (merge patch로 GREETING과 app.conf 교체)"
$K patch configmap app-config --type merge -p \
  '{"data":{"GREETING":"v2 (updated!)","app.conf":"greeting=v2 (updated!)\nlog_level=debug\n"}}'
echo "    수정 완료."

echo
echo "==> 4) 전파 관찰 (최대 ~2분 폴링): env는 그대로(v1), volume 파일은 일정 시간 뒤 v2."
echo "    kubelet의 ConfigMap volume 갱신은 '즉시'가 아니다(sync 주기 + 캐시 TTL, 보통 ~1분)."
for i in $(seq 1 24); do
  line="$($K logs deploy/config-demo --tail=1 2>/dev/null || true)"
  echo "    [t=$((i * 5))s] ${line}"
  if echo "${line}" | grep -q 'file=\[v2'; then
    echo "    -> volume 파일이 v2로 갱신됨! (env는 여전히 v1인 점에 주목)"
    break
  fi
  sleep 5
done

cat <<'EOF'

    해석:
      - env=[v1 ...] 가 끝까지 안 바뀐다 → env는 Pod 생성 시 '복사'된 값. ConfigMap을 바꿔도 그대로.
        반영하려면 Pod를 다시 띄워야 한다(rollout restart).
      - file=[v2 ...] 로 바뀐다 → volume mount는 kubelet이 주기적으로 심볼릭링크를 갱신.
        단, '즉시'가 아니고, 앱이 파일을 '다시 읽어야' 의미가 있다(설정 reload 로직 필요).
      - 실무 해결책:
          (a) 설정 변경 시 CI/CD가 rollout restart를 건다, 또는
          (b) Reloader류가 ConfigMap/Secret 변경을 감지해 자동 재시작 (다음 스크립트 01b).
      - 대규모 팁: 안 바뀌는 설정은 ConfigMap에 immutable: true → kubelet watch 부하 절감.
EOF

echo
echo "    (참고) env를 지금 강제로 갱신하려면 재시작:"
echo "      kubectl --context ${CTX} -n ${NS} rollout restart deployment/config-demo"
echo
echo "다음: bash phase-06-config/scripts/01b-install-reloader.sh"
