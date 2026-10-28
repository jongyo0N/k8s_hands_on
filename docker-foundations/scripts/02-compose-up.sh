#!/usr/bin/env bash
# Docker 기초 / lab 2 — docker compose 멀티서비스 (web + db)
# 실행: bash docker-foundations/scripts/02-compose-up.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../02-compose/docker-compose.yml"
dc() { docker compose -f "${COMPOSE}" "$@"; }

echo "==> 0) compose 파일 검증 (렌더링된 최종 설정)"
dc config >/dev/null && echo "    config OK"

echo
echo "==> 1) 기동 (db가 healthy 된 뒤 web이 뜬다 — depends_on condition)"
dc up -d --build

echo
echo "==> 2) 상태 (web/db의 health 컬럼 확인)"
dc ps

echo
echo "==> 3) web → db 연결 확인 (/health가 db:true 여야 함)"
echo -n "    "; curl -s localhost:8080/health ; echo

echo
echo "==> 4) 내부 DNS 확인: web 컨테이너에서 서비스명 'db'가 해석된다"
dc exec -T web python -c "import socket; print('db ->', socket.gethostbyname('db'))" || true

cat <<'EOF'

    [생각할 거리 — compose의 한계 = k8s가 푸는 문제]
    - `docker compose up --scale web=3` 를 해보면? 호스트 포트 8080을 셋이 공유할 수 없어 충돌.
      → 단일 호스트 compose엔 '여러 복제본 앞단의 로드밸런서'가 없다. 이게 k8s Service의 존재 이유.
    - depends_on은 '기동 순서'만 보장하지 재시도·자가치유는 없다. → k8s는 선언적 수렴으로 해결.
    - compose healthcheck는 이 호스트에서만. → k8s는 probe 결과를 엔드포인트/스케줄링에 반영.
EOF

echo
echo "==> 로그 보기:   docker compose -f ${COMPOSE} logs -f"
echo "==> 정리:        bash docker-foundations/scripts/99-cleanup.sh"
