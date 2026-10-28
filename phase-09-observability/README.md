# Phase 9 — 관측성

> 목표: 메트릭·로그·트레이스를 설계하고, 증상에서 원인으로 가는 경로를 데이터로 연결한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md) 의 Phase 9.

## 전제
- Phase 0의 kind 클러스터(context `kind-k8s-mastery`)
- helm, (선택) jq
- 샘플 앱은 `phase-09` 네임스페이스, 모니터링 스택은 `monitoring` 네임스페이스(helm 릴리스명 `kube-prometheus-stack` 고정)

> ⚠️ 핵심 함정: Prometheus Operator는 `serviceMonitorSelector`로 대상을 고른다. 이 차트 기본값은 `release: <릴리스명>` 라벨이 붙은 ServiceMonitor만 선택한다. 그래서 `01-servicemonitor.yaml`의 `labels.release`가 helm 릴리스명(`kube-prometheus-stack`)과 **반드시** 같아야 스크랩된다.

## 샘플 앱 하나로 세 랩

`manifests/01-demo-app.yaml`의 stdlib Python 앱이 환경변수로 세 랩을 커버한다:
- 기본: RED 메트릭(`/metrics`) 노출 → **lab 01**
- `HIGH_CARDINALITY=true`: 요청마다 고유 `user_id` 라벨 → **lab 02**
- `OTEL_EXPORTER_OTLP_ENDPOINT` 주입: 요청마다 OTLP trace+log → **lab 03**

엔드포인트: `/`(빠른 200) `/slow`(느린 200) `/error`(500) `/healthz` `/metrics`

## 실습 순서

```bash
bash scripts/00-prereqs.sh              # 도구/클러스터 점검
bash scripts/01-prometheus-stack.sh     # 1) 스택 설치 + ServiceMonitor + RED PromQL
bash scripts/02-cardinality.sh          # 2) cardinality 폭발 재현 → 회복
bash scripts/03-otel-correlation.sh     # 3) OTel Collector + trace/log 상관
bash scripts/04-slo-alerts.sh           # 4) SLO 번레이트 다중창 알림
bash scripts/99-cleanup.sh
```

## 각 랩이 가르치는 것

1. **RED 메트릭** — Rate(`rate(http_requests_total[5m])`), Errors(status=~"5.."), Duration(`histogram_quantile(0.99, ...bucket)`). ServiceMonitor가 어떻게 스크랩 대상을 고르는지(release 라벨 함정).
2. **cardinality 폭발** — `user_id` 같은 고유값 라벨이 시계열 수(`prometheus_tsdb_head_series`)를 폭증시켜 Prometheus 메모리를 잡아먹는 과정 관찰 → 라벨 제거로 회복. (TSDB는 라벨 조합마다 별도 시계열.)
3. **trace/log 상관** — 앱이 OTLP로 trace와 log를 내보내고, 로그의 `trace_id`로 한 요청을 끝까지 추적.
4. **SLO 번레이트** — 가용성 99.9% 목표에 대해 빠른 창/느린 창 다중 번레이트 알림으로 alert fatigue 없이 "행동 가능한" 경보만.

## ⚖️ 트레이드오프 & 대안

- **self-hosted(Prometheus) vs managed(Datadog/Grafana Cloud)**: 비용 통제·데이터 소유 vs 운영 부담 제거. 규모가 커질수록 양쪽 다 커진다.
- **로그 저장소 Loki vs Elasticsearch**: 저비용 라벨 인덱스 vs 강력한 전문 검색. "로그로 grep인가 분석인가"로 결정.
- **트레이스 샘플링 head vs tail**: 단순·저비용 vs 에러/느린 요청 보존. 전수 수집은 대개 비현실적.
- **알림 철학**: 원인 기반(시끄러움) vs 증상/SLO 기반(행동 가능). alert fatigue 자체가 장애 요인.

## 완료 기준 ([`NOTES.md`](./NOTES.md)에 답)

1. 한 요청의 지연 원인을 metrics→logs→traces 순으로 좁혀가는 경로
2. cardinality 폭발이 Prometheus를 어떻게 죽이는지와 예방책
3. SLO·에러버짓·번레이트 알림의 관계

## 검증 수준
스크립트 `bash -n` + YAML 파싱만. 이 환경엔 kind 미설치로 클러스터 실행은 미검증.
