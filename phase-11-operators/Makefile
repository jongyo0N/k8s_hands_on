# Makefile — kubebuilder v4 스캐폴드를 간추린 버전.
# 자주 쓰는 타깃만 남겼다. `make help` 로 목록 확인.
#
# 핵심 흐름(랩):
#   make manifests   # 코드의 kubebuilder 마커 → CRD/RBAC yaml 재생성
#   make install     # CRD 를 현재 클러스터에 설치
#   make run         # operator 를 로컬에서(클러스터 밖) 실행 — 개발 루프에 최적

# 설치할 컨트롤러 이미지 태그.
IMG ?= website-operator:latest
# 컨테이너 빌드 도구(docker/podman/nerdctl).
CONTAINER_TOOL ?= docker

# 다운로드되는 툴 바이너리 위치.
LOCALBIN ?= $(shell pwd)/bin
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
KUSTOMIZE ?= $(LOCALBIN)/kustomize

# 툴 버전. controller-gen 은 CRD/RBAC/deepcopy 를 생성한다.
CONTROLLER_TOOLS_VERSION ?= v0.18.0
KUSTOMIZE_VERSION ?= v5.5.0

SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

.PHONY: help
help: ## 이 도움말을 출력한다.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## CRD/RBAC yaml 을 kubebuilder 마커로부터 재생성한다.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## DeepCopy 메서드(zz_generated.deepcopy.go)를 재생성한다.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## gofmt 를 돌린다.
	go fmt ./...

.PHONY: vet
vet: ## go vet 을 돌린다.
	go vet ./...

.PHONY: tidy
tidy: ## go.sum/indirect 의존성을 맞춘다(빌드 전에 한 번 실행).
	go mod tidy

##@ Build

.PHONY: build
build: manifests generate fmt vet ## operator 바이너리를 빌드한다.
	go build -o bin/manager cmd/main.go

.PHONY: run
run: manifests generate fmt vet ## operator 를 로컬(클러스터 밖)에서 실행한다.
	go run ./cmd/main.go

.PHONY: docker-build
docker-build: ## 컨트롤러 이미지를 빌드한다.
	$(CONTAINER_TOOL) build -t $(IMG) .

.PHONY: docker-push
docker-push: ## 컨트롤러 이미지를 푸시한다.
	$(CONTAINER_TOOL) push $(IMG)

##@ Deployment

.PHONY: install
install: manifests kustomize ## CRD 를 현재 클러스터(~/.kube/config)에 설치한다.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## CRD 를 클러스터에서 제거한다.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found -f -

.PHONY: deploy
deploy: manifests kustomize ## 컨트롤러를 클러스터에 배포한다(이미지 필요).
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: kustomize ## 컨트롤러를 클러스터에서 제거한다.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found -f -

##@ Tools (bin/ 아래로 자동 다운로드)

$(LOCALBIN):
	mkdir -p $(LOCALBIN)

.PHONY: controller-gen
controller-gen: $(LOCALBIN) ## controller-gen 을 받는다.
	@test -x $(CONTROLLER_GEN) || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: kustomize
kustomize: $(LOCALBIN) ## kustomize 를 받는다.
	@test -x $(KUSTOMIZE) || GOBIN=$(LOCALBIN) go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)
