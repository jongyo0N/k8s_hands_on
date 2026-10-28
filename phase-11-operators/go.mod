// controller-runtime 와 k8s.io/* 는 쿠버네티스 마이너 버전과 짝을 이룬다:
//   controller-runtime v0.21.x  ↔  k8s.io/* v0.33.x  ↔  Kubernetes 1.33
// 아래 버전은 작성 시점의 안정 조합으로 '핀(pin)'해 두었다.
// 최신 조합은 https://github.com/kubernetes-sigs/controller-runtime/releases 에서 재확인하고,
// 올릴 때는 반드시 `go mod tidy` 로 go.sum/indirect 의존성을 다시 맞춘다.
//
// ⚠ 이 레포는 Go 툴체인 없이도 읽히도록 '직접 제공(direct require)'만 적어 두었다.
//   빌드 전에 반드시 한 번 실행: go mod tidy  (indirect 의존성과 go.sum 을 채운다)
module github.com/jongyo0N/k8s_hands_on/phase-11-operators

go 1.24.0

require (
	k8s.io/api v0.33.0
	k8s.io/apimachinery v0.33.0
	k8s.io/client-go v0.33.0
	sigs.k8s.io/controller-runtime v0.21.0
)
