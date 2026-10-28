# Docker & docker-compose 기초 (Phase 0 이전 선수 과정)

> 쿠버네티스는 "컨테이너 오케스트레이터"다. 컨테이너와 이미지를 몸으로 이해하지 못하면
> k8s의 Pod·probe·volume·Service가 전부 추상적으로만 남는다. 이 모듈은 그 토대를 깔고,
> **docker-compose의 한계가 곧 k8s의 존재 이유**임을 연결한다.
> 상위 커리큘럼: [`../CURRICULUM.md`](../CURRICULUM.md)

## 1. 컨테이너란 무엇인가 (한 문단)

VM이 "가짜 하드웨어"를 만든다면, 컨테이너는 **호스트 커널을 공유하면서 프로세스를 격리**한다. 격리는 리눅스 커널 기능 3종으로 이뤄진다:

- **namespaces** — 무엇을 *볼 수 있는가* (PID, 네트워크, 마운트, user…). 컨테이너 안에서 `ps`가 자기 프로세스만 보는 이유.
- **cgroups** — 무엇을 *얼마나 쓸 수 있는가* (CPU, 메모리). k8s의 requests/limits가 결국 이걸 설정한다(Phase 7).
- **union filesystem** (overlayfs) — 이미지 레이어를 쌓아 읽기전용 + 쓰기 레이어로 합침. "레이어 캐싱"의 근거.

> 핵심: 컨테이너는 "가벼운 VM"이 아니라 **격리된 리눅스 프로세스**다. 그래서 커널 취약점은 공유되고(→ Phase 8의 gVisor/Kata 격리 트레이드오프), PID 1 시그널 처리 같은 "프로세스"의 상식이 그대로 적용된다.

## 2. 이미지 vs 컨테이너

- **이미지** = 불변 템플릿(레이어의 스택 + 메타데이터). `Dockerfile`로 빌드.
- **컨테이너** = 이미지를 실행한 인스턴스(이미지 + 쓰기 레이어 + 실행 상태).
- 태그 vs **다이제스트**: `nginx:1.27`은 움직이는 포인터, `nginx@sha256:...`은 불변. 재현성·공급망 보안이 중요하면 다이제스트 고정(Phase 8).

## 3. Dockerfile 모범 사례 — [`01-dockerfile/Dockerfile`](./01-dockerfile/Dockerfile)

이 예제 하나에 실무 교훈 3가지가 들어있다.

| 기법 | 왜 | ⚖️ 트레이드오프 |
|---|---|---|
| **멀티스테이지** | 빌드 도구(컴파일러·캐시)를 최종 이미지에서 제거 → 작고 안전 | Dockerfile 복잡도↑ |
| **레이어 캐싱 순서** | `requirements.txt`를 소스보다 먼저 COPY → 의존성 안 바뀌면 재설치 생략 | 순서를 잘못 짜면 캐시 무효화로 매번 느림 |
| **비root(USER)** | 컨테이너 탈출 시 피해 축소 | 포트<1024 바인딩 불가 등 일부 제약 |
| **exec form CMD** | PID 1이 앱 → SIGTERM 직접 수신(graceful shutdown) | shell form 쓰면 시그널이 앱까지 안 감(흔한 함정) |

### ⚖️ base 이미지 선택

- **`-slim`** (예제 선택): 적당히 작고 호환성 좋음 / 완전 최소는 아님
- **`alpine`**: 아주 작음 / musl libc라 glibc 전제 바이너리·wheel에서 문제 가능
- **`distroless` / chainguard**: 셸·패키지매니저 없음 → 공격 표면 최소 / 디버깅 어려움(셸이 없음), 빌드 난도↑
- **full(`python:3.12`)**: 디버깅 편함 / 크고 CVE 많음

> 규칙: "가장 작은 이미지"가 항상 정답은 아니다. 디버깅 용이성·호환성과 저울질한다.

## 4. docker-compose — [`02-compose/docker-compose.yml`](./02-compose/docker-compose.yml)

compose는 **단일 호스트에서 여러 컨테이너를 선언적으로** 묶는 도구다. 로컬 개발·통합 테스트의 사실상 표준.

이 예제가 보여주는 것:
- **service 간 DNS**: `web`이 `db`라는 이름으로 접속(내부 네트워크). → k8s Service 디스커버리의 축소판.
- **healthcheck + depends_on condition**: db가 `healthy`가 될 때까지 web 시작 보류. → k8s의 readiness probe + initContainer 조합의 축소판.
- **named volume**: 컨테이너를 지워도 DB 데이터 유지. → k8s PV/PVC의 축소판.
- **포트 노출 최소화**: db는 호스트에 노출하지 않음.

## 5. ⚖️ compose vs Kubernetes — 언제 무엇을

compose의 한계가 정확히 k8s가 푸는 문제다:

| compose (단일 호스트) | Kubernetes (클러스터) |
|---|---|
| service | Deployment + **Service**(복제본 앞단 LB) |
| `--scale`는 포트 충돌 | ReplicaSet + Service로 N개 복제·LB |
| `depends_on`(기동 순서만) | 선언적 수렴·자가치유·재시도 |
| healthcheck(이 호스트만) | probe → 엔드포인트/스케줄링에 반영 |
| named volume(이 호스트) | PV/PVC(네트워크 스토리지, 재배치) |
| 수동 재시작 | 노드 장애 시 자동 재스케줄 |

**compose로 충분한 경우**: 로컬 개발 환경, CI의 통합 테스트, 단일 서버 사이드 프로젝트. 
**k8s가 필요해지는 신호**: 다중 노드/무중단 배포/자동 스케일/자가치유/선언적 운영이 필요할 때.

> 마이그레이션 도구 `kompose`가 compose→k8s 매니페스트를 변환해주지만, 1:1이 아니다(위 표의 간극 때문). 변환은 출발점일 뿐 손질이 필요하다. — 이 "간극 메우기"가 Phase 1~13의 내용이다.

## 실습 순서

```bash
# 사전: docker 데몬 실행 중 (Docker Desktop / OrbStack / Colima)
bash docker-foundations/scripts/01-build-run.sh    # 빌드·실행·레이어·PID 1·비root 확인
bash docker-foundations/scripts/02-compose-up.sh   # web+db 멀티서비스, 내부 DNS, 한계 체감
bash docker-foundations/scripts/99-cleanup.sh      # 정리
```

## 완료 기준 ([`NOTES.md`](./NOTES.md)에 답)

1. 컨테이너를 "가벼운 VM"이 아니라 무엇으로 설명하는가? (namespaces/cgroups/unionfs)
2. Dockerfile에서 `requirements.txt`를 소스보다 먼저 COPY하는 이유는?
3. CMD를 exec form으로 써야 graceful shutdown이 되는 이유는? (PID 1 시그널)
4. `docker compose up --scale web=3`이 실패하는 이유와, k8s가 이를 어떻게 푸는지?
5. compose healthcheck와 k8s probe의 차이는?
