# k8s_hands_on

쿠버네티스를 실무자 수준(internals · 설계 결정 · 프로덕션 디버깅)으로 학습하기 위한 실습 레포.

## 구성

- **[`CURRICULUM.md`](./CURRICULUM.md)** — 전체 커리큘럼(14개 Phase). 각 Phase의 목표·핵심 주제·랩·트레이드오프·완료 기준.
- **`docker-foundations/`** — Phase 0 이전 선수 과정(컨테이너·이미지·docker-compose).
- **`phase-XX-<topic>/`** — Phase별 실습 코드와 기록.
  - `README.md` — 그 Phase의 실행 방법과 완료 기준
  - `scripts/` 또는 매니페스트 — 실제 실행 가능한 랩
  - `NOTES.md` — 관찰·원인·트레이드오프를 적는 학습 기록(채워나감)

## 시작하기

```bash
# 0) 컨테이너 기초(선택): docker/compose
cat docker-foundations/README.md
# 1) kind 등 도구 점검 후 Phase 0부터
bash phase-00-setup/scripts/00-check-tools.sh
cat phase-00-setup/README.md
```

> 실제 랩 실행에는 `kind`가 필요하다(`brew install kind`). 각 Phase README에 전제·실행 순서가 있다.

## 진행 현황

| Phase | 주제 | 상태 |
|---|---|---|
| — | Docker & docker-compose 기초 | ✅ (빌드·실행 검증) |
| 0 | 환경 구축 & 도구 | ✅ |
| 1 | 아키텍처 & 선언적 모델 | ✅ |
| 2 | 워크로드 & Pod 심화 | ✅ |
| 3 | 네트워킹 I — Service & DNS | ✅ |
| 4 | 네트워킹 II — Gateway API, CNI, 메시 | ✅ |
| 5 | 스토리지 | ✅ |
| 6 | 구성·시크릿·패키징 | ✅ |
| 7 | 스케줄링 & 오토스케일링 | ✅ |
| 8 | 보안 & 하드닝 | ✅ |
| 9 | 관측성 | ✅ |
| 10 | 클러스터 수명주기 & 운영 | ✅ |
| 11 | 확장 — CRD·Operator·API 내부 | ✅ |
| 12 | GitOps & 배포 파이프라인 | ✅ |
| 13 | 프로덕션 심화 & 캡스톤 | ✅ |

> 검증 수준: Docker 모듈과 Phase 13(kustomize)은 실제 렌더/빌드까지 검증했고, 나머지 Phase는 스크립트 `bash -n` + YAML 파싱까지 정적 검증했다(로컬에 kind가 없어 클러스터 실행은 미검증). 실제 클러스터에서 처음 돌릴 때 이미지 태그·helm 차트 버전을 한 번 확인할 것.

학습 방법과 사용법은 `CURRICULUM.md`의 부록 B 참고.
