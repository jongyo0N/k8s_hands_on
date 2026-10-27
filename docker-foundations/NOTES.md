# Docker & compose 기초 — NOTES

> 실습하며 ①무엇을 했는지 ②관찰한 것 ③원인·이유 ④트레이드오프를 적는다.

## 1. 무엇을 했는가
- [ ] 멀티스테이지 이미지 빌드 (`01-build-run.sh`)
- [ ] 단독 컨테이너 실행 + 뜯어보기
- [ ] compose 멀티서비스(web+db) 기동 (`02-compose-up.sh`)

## 2. 관찰한 것 (사실만)
- 최종 이미지 크기: ______ MB  / `docker history`에서 가장 큰 레이어: ______
- 컨테이너 안 PID 1 프로세스: ______ (python? sh?)
- `id` 결과(비root?): ______
- compose에서 web이 뜨기까지 db를 기다린 정황: ______
- `web`에서 `db` 이름 해석 결과 IP: ______

## 3. 원인·이유
- `requirements.txt`를 먼저 COPY했을 때 재빌드가 빨라진 이유:
  > ______ (레이어 캐시)
- db를 호스트 포트로 노출하지 않았는데 web이 접속되는 이유:
  > ______ (compose 내부 네트워크 + 서비스 DNS)

## 4. 배운 트레이드오프
- base 이미지: slim vs alpine vs distroless — 내 앱엔 ______ 가 적합. 이유: ______
- compose로 충분한 상황 vs k8s가 필요한 상황(내 프로젝트 기준): ______

## 5. 완료 기준 — 답하기
1. 컨테이너 = ______ (가벼운 VM이 아니라…)
2. requirements를 먼저 COPY하는 이유: ______
3. exec form CMD와 graceful shutdown: ______
4. `--scale web=3`이 실패하는 이유 / k8s의 해법: ______
5. compose healthcheck vs k8s probe: ______

---
_다음: `../phase-00-setup/`(kind 클러스터)로 진행._
