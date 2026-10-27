# k8s_hands_on

쿠버네티스를 실무자 수준(internals · 설계 결정 · 프로덕션 디버깅)으로 학습하기 위한 실습 레포.

## 구성

- **[`CURRICULUM.md`](./CURRICULUM.md)** — 전체 커리큘럼(14개 Phase). 각 Phase의 목표·핵심 주제·랩·트레이드오프·완료 기준.
- **`phase-XX-<topic>/`** — Phase별 실습 코드와 기록.
  - `README.md` — 그 Phase의 실행 방법과 완료 기준
  - `scripts/` 또는 매니페스트 — 실제 실행 가능한 랩
  - `NOTES.md` — 관찰·원인·트레이드오프를 적는 학습 기록(채워나감)

## 시작하기

```bash
# 도구 점검 후 Phase 0부터
bash phase-00-setup/scripts/00-check-tools.sh
cat phase-00-setup/README.md
```

## 진행 현황

| Phase | 주제 | 상태 |
|---|---|---|
| 0 | 환경 구축 & 도구 | ✅ 코드 작성됨 |
| 1 | 아키텍처 & 선언적 모델 | ⬜ 예정 |
| 2 | 워크로드 & Pod 심화 | ⬜ 예정 |
| 3 | 네트워킹 I — Service & DNS | ⬜ 예정 |
| 4 | 네트워킹 II — Gateway API, CNI, 메시 | ⬜ 예정 |
| 5 | 스토리지 | ⬜ 예정 |
| 6 | 구성·시크릿·패키징 | ⬜ 예정 |
| 7 | 스케줄링 & 오토스케일링 | ⬜ 예정 |
| 8 | 보안 & 하드닝 | ⬜ 예정 |
| 9 | 관측성 | ⬜ 예정 |
| 10 | 클러스터 수명주기 & 운영 | ⬜ 예정 |
| 11 | 확장 — CRD·Operator·API 내부 | ⬜ 예정 |
| 12 | GitOps & 배포 파이프라인 | ⬜ 예정 |
| 13 | 프로덕션 심화 & 캡스톤 | ⬜ 예정 |

학습 방법과 사용법은 `CURRICULUM.md`의 부록 B 참고.
