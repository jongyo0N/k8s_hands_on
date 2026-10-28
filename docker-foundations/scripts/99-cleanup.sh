#!/usr/bin/env bash
# Docker 기초 — 정리
# 실행: bash docker-foundations/scripts/99-cleanup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../02-compose/docker-compose.yml"

echo "==> compose 스택 내리기 (-v: named volume까지 삭제)"
docker compose -f "${COMPOSE}" down -v || true

echo "==> 단독 실행 컨테이너 제거"
docker rm -f df-web >/dev/null 2>&1 || true

echo "==> 빌드 이미지 제거"
docker rmi df-web:local >/dev/null 2>&1 || true

echo "    완료."
