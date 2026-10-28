#!/usr/bin/env bash
# Phase 11 / lab 1~2 — reconcile 의 멱등성과 self-healing 을 관찰한다.
#
# 선행 조건:
#   1) 클러스터 존재(Phase 0 의 kind 클러스터 등)
#   2) CRD 설치됨:        make install
#   3) operator 실행 중:   make run     (다른 터미널에서 띄워 둘 것)
#
# 실행: bash phase-11-operators/scripts/01-observe-reconcile.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE="${SCRIPT_DIR}/../config/samples/website.yaml"
NS=default
NAME=hello

kc() { kubectl ${KUBE_CONTEXT:+--context "${KUBE_CONTEXT}"} "$@"; }

echo "==> 1. 샘플 Website 적용"
kc apply -f "${SAMPLE}"

echo
echo "==> 2. 컨트롤러가 만든 자식 리소스 확인 (owner reference 로 Website 에 매달림)"
kc -n "${NS}" wait --for=condition=Available deploy/"${NAME}" --timeout=90s || true
kc -n "${NS}" get website,deploy,svc -l app.kubernetes.io/instance="${NAME}" -o wide

echo
echo "==> 3. owner reference 확인 — Deployment 의 주인이 Website 인가?"
kc -n "${NS}" get deploy "${NAME}" -o jsonpath='{.metadata.ownerReferences}' ; echo

echo
echo "==> 4. self-healing: 자식 Deployment 를 강제로 지워 본다"
echo "    → Owns() 가 이벤트를 잡아 reconcile 가 즉시 되살린다(level-triggered)."
kc -n "${NS}" delete deploy "${NAME}"
sleep 3
kc -n "${NS}" get deploy "${NAME}" -o wide || echo "    (아직 복구 전이면 잠시 후 다시 확인)"

echo
echo "==> 5. 멱등성: replicas 를 3 으로 바꿔도, 10번을 reconcile 해도 결과는 '3개'로 수렴"
kc -n "${NS}" patch website "${NAME}" --type=merge -p '{"spec":{"replicas":3}}'
sleep 3
kc -n "${NS}" get deploy "${NAME}" -o jsonpath='{.spec.replicas}' ; echo " (desired replicas)"

echo
echo "==> 6. status subresource 확인 (컨트롤러가 관찰한 실제 상태)"
kc -n "${NS}" get website "${NAME}" -o jsonpath='{.status}' ; echo

echo
echo "다음: bash phase-11-operators/scripts/02-observe-gc-finalizer.sh"
