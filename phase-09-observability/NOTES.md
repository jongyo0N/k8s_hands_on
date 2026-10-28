# Phase 9 — NOTES (관측성)

## 1. 무엇을 했는가
- [ ] kube-prometheus-stack 설치 + demo-app ServiceMonitor 연결
- [ ] RED 메트릭 PromQL 쿼리
- [ ] HIGH_CARDINALITY 켜서 시계열 폭증 재현 → 회복
- [ ] OTel Collector로 trace/log 상관
- [ ] SLO 번레이트 알림 적용

## 2. 관찰 (사실만)
- Prometheus Targets에서 demo-app이 UP 됐나? (안 되면 release 라벨 확인): ______
- `rate(http_requests_total[5m])` 값: ______ / p99 duration: ______
- HIGH_CARDINALITY 전/후 `prometheus_tsdb_head_series`: ______ → ______
- 로그의 trace_id로 trace를 찾았나?: ______

## 3. 원인·이유
- ServiceMonitor를 만들었는데 스크랩이 안 될 때 가장 흔한 원인:
  > ______ (serviceMonitorSelector release 라벨)
- user_id 라벨이 시계열을 폭증시키는 메커니즘:
  > ______ (라벨 조합마다 별도 시계열)

## 4. 트레이드오프
- 우리 로그: Loki vs Elasticsearch — 선택과 근거:
  > ______
- 트레이스 샘플링 head vs tail — 우리 상황엔:
  > ______

## 5. 완료 기준 — 답하기
1. 지연 원인을 metrics→logs→traces로 좁히는 경로:
   > ______
2. cardinality 폭발이 Prometheus를 죽이는 과정 + 예방책:
   > ______
3. SLO·에러버짓·번레이트 알림의 관계:
   > ______

---
_다음: Phase 10(수명주기)으로._
