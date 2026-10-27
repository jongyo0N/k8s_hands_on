"""
작은 HTTP 서비스 — 컨테이너/compose 실습용.
- GET /        : 호스트명 + 버전 (컨테이너 교체 시 호스트명이 바뀌는 걸로 '불변 인프라'를 체감)
- GET /health  : DATABASE_URL이 있으면 DB 연결을 확인. compose healthcheck / k8s readiness가 이 엔드포인트를 본다.

NOTE(트레이드오프): 여기서는 Flask 내장 개발 서버를 쓴다. 실무 프로덕션이라면
gunicorn/uvicorn 같은 WSGI/ASGI 서버로 띄운다(동시성·안정성). 학습 단순화를 위한 선택.
"""
import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "1.0.0")


def db_status():
    """DATABASE_URL이 설정됐을 때만 DB 연결을 확인. 미설정이면 None(체크 생략)."""
    url = os.environ.get("DATABASE_URL")
    if not url:
        return None
    try:
        import psycopg2

        conn = psycopg2.connect(url, connect_timeout=2)
        conn.close()
        return True
    except Exception:
        return False


@app.get("/")
def index():
    return jsonify(
        message="hello from container",
        host=socket.gethostname(),
        version=VERSION,
    )


@app.get("/health")
def health():
    db = db_status()
    # DB가 설정됐는데 연결 실패면 503 — 의존성이 아직 안 떴다는 신호.
    if db is False:
        return jsonify(status="unhealthy", db=False), 503
    return jsonify(status="ok", db=db)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
