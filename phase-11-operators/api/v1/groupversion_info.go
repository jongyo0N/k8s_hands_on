// Package v1 은 apps.example.com/v1 API 그룹의 타입을 담는다.
// +kubebuilder:object:generate=true
// +groupName=apps.example.com
package v1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
	// GroupVersion 은 이 API 그룹/버전의 식별자다 (apps.example.com/v1).
	// CRD yaml의 spec.group / versions[].name 과 반드시 일치해야 한다.
	GroupVersion = schema.GroupVersion{Group: "apps.example.com", Version: "v1"}

	// SchemeBuilder 는 Go 타입을 GroupVersionKind 에 등록하는 헬퍼다.
	// 매니저의 scheme 에 AddToScheme 으로 주입하면, 클라이언트가
	// Website 오브젝트를 (역)직렬화하고 REST 매핑을 찾을 수 있게 된다.
	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

	// AddToScheme 은 cmd/main.go 에서 호출한다.
	AddToScheme = SchemeBuilder.AddToScheme
)
