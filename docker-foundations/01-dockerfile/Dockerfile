# syntax=docker/dockerfile:1
#
# 멀티스테이지 빌드: 빌드 전용 도구(컴파일러·pip 캐시)가 최종 이미지에 남지 않게 분리.
# 교훈 3가지가 이 파일에 들어있다:
#   1) 레이어 캐싱 — 자주 안 바뀌는 것(의존성)을 먼저, 자주 바뀌는 것(소스)을 나중에 COPY
#   2) 작은 런타임 이미지 — slim 베이스 + builder 산출물만 복사
#   3) 비root 실행 — 공격 표면 축소 (k8s securityContext runAsNonRoot로 이어짐: Phase 8)

############################
# 1) builder — 의존성을 venv에 설치
############################
FROM python:3.12-slim AS builder
WORKDIR /app

# requirements만 먼저 복사: 소스가 바뀌어도 의존성이 그대로면 이 레이어는 캐시 재사용.
COPY requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

############################
# 2) runtime — 실행 전용
############################
FROM python:3.12-slim AS runtime

# 비root 사용자(고정 UID). k8s에서 runAsNonRoot/runAsUser와 맞물린다.
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY app.py .

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PORT=8080

EXPOSE 8080
USER 10001

# HEALTHCHECK: docker/compose는 이걸 본다.
#   ⚠️ 단, k8s는 Dockerfile HEALTHCHECK를 '무시'하고 Pod spec의 probe를 쓴다(Phase 2).
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# exec form(JSON 배열): PID 1이 python이 되어 SIGTERM을 직접 받는다 → graceful shutdown.
# shell form("python app.py")이면 /bin/sh가 PID 1이 되어 시그널이 앱에 전달되지 않는 함정.
CMD ["python", "app.py"]
