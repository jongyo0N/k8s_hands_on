/*
website_types.go — Website CRD 의 Go 스키마.

여기 선언한 구조체 + kubebuilder 마커가 `make manifests` 시 controller-gen 을 통해
config/crd/bases/apps.example.com_websites.yaml (OpenAPI v3 스키마) 로 변환된다.
즉, "코드가 곧 스키마의 진실의 원천(source of truth)"이다.
*/
package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// WebsiteSpec 은 사용자가 '원하는 상태(desired state)'를 선언하는 곳이다.
// 컨트롤러는 이 spec 만 보고 Deployment/Service 를 매번 재계산한다(level-triggered).
type WebsiteSpec struct {
	// Image 는 서비스가 실행할 컨테이너 이미지(repo:tag).
	// 필수값이며 빈 문자열은 거부된다(API server 의 OpenAPI 검증 단계에서).
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Image string `json:"image"`

	// Host 는 외부에 노출할 호스트네임. Ingress/Gateway 라우팅 키이자,
	// finalizer 데모에서 "외부 DNS 레코드"의 키로 쓰인다.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Host string `json:"host"`

	// Replicas 는 원하는 Pod 복제본 수. 0 이상, 미지정 시 1.
	// default 마커 덕분에 CR 에 값이 없어도 API server 가 1 을 채워준다
	// (defaulting 은 OpenAPI 스키마의 default 로 처리 — mutating webhook 불필요).
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:default=1
	// +optional
	Replicas int32 `json:"replicas,omitempty"`

	// Port 는 컨테이너가 리슨하는 포트. 미지정 시 80.
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=65535
	// +kubebuilder:default=80
	// +optional
	Port int32 `json:"port,omitempty"`
}

// WebsiteStatus 는 컨트롤러가 관찰한 '실제 상태(observed state)'를 기록한다.
// status 는 subresource 로 분리되어(아래 +kubebuilder:subresource:status),
// spec 과 독립적으로 갱신된다 → 컨트롤러의 status 쓰기가 사용자의 spec generation 을
// 건드리지 않는다(무한 reconcile 루프 방지의 한 축).
type WebsiteStatus struct {
	// ObservedGeneration 은 컨트롤러가 마지막으로 처리한 spec 의 generation.
	// status.observedGeneration < metadata.generation 이면 "아직 반영 중"이라는 뜻.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// ReadyReplicas 는 현재 Ready 상태인 Pod 수(소유한 Deployment status 에서 미러).
	// +optional
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`

	// Phase 는 사람이 읽기 좋은 상위 상태 요약(Pending/Progressing/Available).
	// +optional
	Phase string `json:"phase,omitempty"`

	// Conditions 는 표준 condition 배열. Ready 타입 하나를 유지한다.
	// listType=map + listMapKey=type 마커로 server-side apply 시
	// type 을 키로 한 "원소별 병합(merge by key)"이 가능해진다.
	// +optional
	// +listType=map
	// +listMapKey=type
	// +patchStrategy=merge
	// +patchMergeKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:shortName=web,categories=all
// +kubebuilder:printcolumn:name="Host",type=string,JSONPath=`.spec.host`
// +kubebuilder:printcolumn:name="Image",type=string,JSONPath=`.spec.image`
// +kubebuilder:printcolumn:name="Desired",type=integer,JSONPath=`.spec.replicas`
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=`.status.readyReplicas`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// Website 는 "웹 서비스 한 개"를 선언적으로 표현하는 커스텀 리소스다.
// 사용자는 image/host/replicas 만 적고, 컨트롤러가 Deployment+Service 를 만든다.
type Website struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   WebsiteSpec   `json:"spec,omitempty"`
	Status WebsiteStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// WebsiteList 는 Website 의 목록 타입(list/watch 응답에 쓰인다).
type WebsiteList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Website `json:"items"`
}

func init() {
	// 타입을 scheme 빌더에 등록 → 클라이언트가 이 GVK 를 인식한다.
	SchemeBuilder.Register(&Website{}, &WebsiteList{})
}
