#!/usr/bin/env bash
# Docker 기초 / lab 1 — 이미지 빌드 · 실행 · 뜯어보기
# 실행: bash docker-foundations/scripts/01-build-run.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="${SCRIPT_DIR}/../01-dockerfile"
IMG="df-web:local"

echo "==> 1) 멀티스테이지 빌드"
docker build -t "${IMG}" "${CTX}"

echo
echo "==> 2) 이미지 크기와 레이어 (멀티스테이지·slim의 효과)"
docker image ls "${IMG}"
echo "    레이어 히스토리:"
docker history "${IMG}"

echo
echo "==> 3) 컨테이너 실행 (DB 없이 — /health는 db=null로 ok)"
docker rm -f df-web >/dev/null 2>&1 || true
docker run -d --name df-web -p 8080:8080 "${IMG}"
echo "    기동 대기..."
sleep 2

echo
echo "==> 4) 응답 확인"
curl -s localhost:8080/ ; echo
curl -s localhost:8080/health ; echo

echo
echo "==> 5) 누가 PID 1인가? (exec form이라 python이 PID 1 → SIGTERM 직접 수신)"
# slim 이미지엔 ps가 없다 → 컨테이너 PID 네임스페이스의 1번 프로세스를 /proc에서 직접 읽는다.
echo -n "    /proc/1/comm = "; docker exec df-web cat /proc/1/comm

echo
echo "==> 6) 비root로 도는지 확인 (USER 10001)"
docker exec df-web id

echo
echo "==> 정리"
docker rm -f df-web >/dev/null
echo "    컨테이너 제거 완료. (이미지는 02-compose에서 재사용)"
