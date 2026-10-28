/*
website_controller.go — Website CR 의 reconcile 루프.

이 파일이 Phase 11 랩의 심장이다. 아래 네 가지 개념이 코드로 구현되어 있다:
  (a) 멱등(idempotent) · level-triggered reconcile  — ensureDeployment/ensureService
  (b) finalizer 로 외부 리소스 정리                   — reconcileDelete
  (c) owner reference 기반 GC                         — controllerutil.SetControllerReference
  (d) status subresource 갱신(무한 루프 방지)         — updateStatus

reconcile 의 핵심 계약:
  "현재 상태가 무엇이든, spec 을 보고 원하는 상태로 '수렴'시킨다. 몇 번을 호출해도
   결과가 같아야 한다(멱등). 이벤트를 놓쳐도 다음 호출에서 바로잡는다(level-triggered)."
*/
package controller

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	webappv1 "github.com/jongyo0N/k8s_hands_on/phase-11-operators/api/v1"
)

const (
	// websiteFinalizer — 이 문자열이 metadata.finalizers 에 들어있는 동안
	// API server 는 "삭제 요청(deletionTimestamp)"만 찍고 실제 삭제를 보류한다.
	// 우리가 정리를 끝내고 finalizer 를 빼면 그제서야 오브젝트가 사라진다.
	websiteFinalizer = "apps.example.com/finalizer"

	typeAvailable   = "Available"
	reasonReady     = "DeploymentReady"
	reasonNotReady  = "DeploymentNotReady"
	reasonReconcile = "Reconciling"
)

// WebsiteReconciler 는 Website 를 reconcile 한다.
type WebsiteReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder
}

// RBAC: controller-gen 이 아래 마커들을 읽어 config/rbac/role.yaml 을 만든다.
// 컨트롤러가 접근하는 모든 리소스를 빠짐없이 적어야 한다(최소 권한).
// +kubebuilder:rbac:groups=apps.example.com,resources=websites,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps.example.com,resources=websites/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps.example.com,resources=websites/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=events,verbs=create;patch

// Reconcile 은 Website 하나의 이벤트(또는 소유한 Deployment/Service 의 이벤트)마다 불린다.
func (r *WebsiteReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// 1) 현재 CR 을 읽는다. 항상 "읽고 → 비교하고 → 맞춘다"로 시작한다.
	var website webappv1.Website
	if err := r.Get(ctx, req.NamespacedName, &website); err != nil {
		// NotFound = 이미 삭제됨. 소유한 자식들은 owner reference 로 GC 가 치운다.
		// 여기서 할 일은 없다. 에러로 재큐잉하지 않도록 조용히 종료.
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// 2) 삭제 중인가? deletionTimestamp 가 찍혔으면 정리 경로로 분기한다.
	if !website.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, &website)
	}

	// 3) finalizer 가 없으면 먼저 등록한다. 이게 자식/외부 리소스를 '만들기 전에'
	//    선행되어야, 중간에 삭제돼도 정리 훅이 반드시 돌 기회를 갖는다.
	if !controllerutil.ContainsFinalizer(&website, websiteFinalizer) {
		controllerutil.AddFinalizer(&website, websiteFinalizer)
		if err := r.Update(ctx, &website); err != nil {
			return ctrl.Result{}, fmt.Errorf("finalizer 등록 실패: %w", err)
		}
		// 방금 오브젝트를 바꿨으니 깔끔하게 반환한다. Update 이벤트가 다음 reconcile 을
		// 다시 큐잉하므로 이어서 진행된다(level-triggered 라 손해가 없다).
		return ctrl.Result{}, nil
	}

	// 4) 원하는 상태로 수렴시킨다 — 멱등하게.
	if err := r.ensureDeployment(ctx, &website); err != nil {
		r.event(&website, corev1.EventTypeWarning, reasonReconcile, "Deployment 조정 실패: "+err.Error())
		return ctrl.Result{}, err
	}
	if err := r.ensureService(ctx, &website); err != nil {
		r.event(&website, corev1.EventTypeWarning, reasonReconcile, "Service 조정 실패: "+err.Error())
		return ctrl.Result{}, err
	}

	// 5) 관찰한 실제 상태를 status 에 반영한다(바뀐 경우에만 — 무한 루프 방지).
	if err := r.updateStatus(ctx, &website); err != nil {
		return ctrl.Result{}, err
	}

	log.Info("reconcile 완료", "website", req.NamespacedName, "generation", website.Generation)
	// 시간 기반 requeue 를 쓰지 않는다. Deployment status 가 바뀌면 Owns() 가 자동으로
	// 다시 큐잉하므로, polling 대신 "이벤트 기반 + level-triggered"로 충분하다.
	return ctrl.Result{}, nil
}

// ensureDeployment 은 Website spec 에 맞는 Deployment 가 존재하도록 보장한다.
//
// ── 멱등성의 핵심 ───────────────────────────────────────────────────────────
// CreateOrUpdate 는 (1) 오브젝트를 Get 하고 (2) mutate 함수로 '원하는 상태'를 써넣은 뒤
// (3) 실제 diff 가 있을 때만 Create/Update 한다. mutate 안에서는 "현재 값에 더하지" 말고
// 항상 "spec 으로부터 절대값을 재계산"해야 한다. 그래야 몇 번을 호출해도 결과가 같다.
//
// ✗ 비멱등(안티패턴) 예시 — 이렇게 짜면 랩에서 문제가 관찰된다:
//
//	// (A) 존재 여부를 안 보고 무조건 Create → 두 번째 reconcile 부터 AlreadyError,
//	//     영원히 에러 재큐잉. edge-triggered 사고의 전형적 실패.
//	_ = r.Create(ctx, desiredDeployment)
//
//	// (B) 현재 replicas 에 "더하기" → reconcile 가 불릴 때마다 replicas 가 증가.
//	//     이벤트가 몇 번 오느냐에 결과가 의존한다(= edge-triggered, 비멱등).
//	deploy.Spec.Replicas = ptr(*deploy.Spec.Replicas + website.Spec.Replicas)
//
// ✓ 멱등(아래 구현) — 항상 spec 의 절대값으로 덮어쓴다. 10번을 불러도 상태는 하나로 수렴.
func (r *WebsiteReconciler) ensureDeployment(ctx context.Context, website *webappv1.Website) error {
	labels := labelsForWebsite(website.Name)

	// Name/Namespace 만 채운 '키'를 넘긴다. 나머지는 mutate 안에서 채운다.
	deploy := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: website.Name, Namespace: website.Namespace},
	}

	op, err := controllerutil.CreateOrUpdate(ctx, r.Client, deploy, func() error {
		// 아래는 전부 '절대값' 할당이다. 현재 deploy 가 어떤 값이었든 덮어쓴다.
		replicas := website.Spec.Replicas
		deploy.Labels = labels
		deploy.Spec.Replicas = &replicas
		deploy.Spec.Selector = &metav1.LabelSelector{MatchLabels: labels}
		deploy.Spec.Template = corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{Labels: labels},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name:  "web",
					Image: website.Spec.Image,
					Ports: []corev1.ContainerPort{{
						Name:          "http",
						ContainerPort: website.Spec.Port,
					}},
				}},
			},
		}
		// (c) owner reference — 이 Deployment 의 '주인'이 Website 임을 새긴다.
		// controller=true 로 박히므로, Website 가 지워지면 GC 가 이 Deployment 를 따라 지운다.
		// 주의: selector 는 생성 후 immutable 이지만, 매번 같은 값을 쓰므로 diff 가 없어 안전하다.
		return controllerutil.SetControllerReference(website, deploy, r.Scheme)
	})
	if err != nil {
		return fmt.Errorf("deployment 조정 실패: %w", err)
	}
	if op != controllerutil.OperationResultNone {
		logf.FromContext(ctx).Info("Deployment "+string(op), "name", deploy.Name)
	}
	return nil
}

// ensureService 는 Website spec 에 맞는 ClusterIP Service 가 존재하도록 보장한다. 역시 멱등.
func (r *WebsiteReconciler) ensureService(ctx context.Context, website *webappv1.Website) error {
	labels := labelsForWebsite(website.Name)

	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: website.Name, Namespace: website.Namespace},
	}

	op, err := controllerutil.CreateOrUpdate(ctx, r.Client, svc, func() error {
		svc.Labels = labels
		// ⚠ 멱등 함정: spec.clusterIP 는 생성 시 API server 가 할당하는 immutable 필드다.
		//   mutate 안에서 절대 건드리지 않는다. Selector/Ports 등 "우리가 소유한" 필드만 쓴다.
		svc.Spec.Selector = labels
		svc.Spec.Type = corev1.ServiceTypeClusterIP
		svc.Spec.Ports = []corev1.ServicePort{{
			Name:       "http",
			Port:       80,
			TargetPort: intstr.FromInt(int(website.Spec.Port)),
			Protocol:   corev1.ProtocolTCP,
		}}
		return controllerutil.SetControllerReference(website, svc, r.Scheme)
	})
	if err != nil {
		return fmt.Errorf("service 조정 실패: %w", err)
	}
	if op != controllerutil.OperationResultNone {
		logf.FromContext(ctx).Info("Service "+string(op), "name", svc.Name)
	}
	return nil
}

// reconcileDelete 는 Website 가 삭제될 때(= deletionTimestamp 가 찍힌 뒤) 불린다.
//
// ── (b) finalizer 가 없으면 왜 리소스가 누수되는가 ─────────────────────────────
// in-cluster 자식(Deployment/Service)은 owner reference 덕에 finalizer 없이도 GC 가
// 정리한다. 문제는 "클러스터 밖" 리소스다 — 외부 DNS 레코드, 클라우드 LB, S3 버킷, 외부 DB.
// GC 는 이들의 존재를 모른다. finalizer 가 없으면 Website 가 사라지는 순간 정리 훅을 돌릴
// 기회 자체가 없어져 외부 리소스가 영원히 남는다(= 누수, 비용·보안 리스크).
// 그래서 외부 리소스를 만지는 operator 는 finalizer 로 삭제를 '붙잡아' 정리를 보장한다.
func (r *WebsiteReconciler) reconcileDelete(ctx context.Context, website *webappv1.Website) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	if !controllerutil.ContainsFinalizer(website, websiteFinalizer) {
		// 정리가 이미 끝났고 finalizer 도 빠진 상태. 할 일 없음.
		return ctrl.Result{}, nil
	}

	// 외부 리소스 정리(여기서는 "외부 DNS 레코드 해제"를 로그로 시뮬레이션).
	// 실제 operator 라면 여기서 Route53/Cloudflare API 를 호출한다.
	if err := r.deprovisionExternalDNS(ctx, website); err != nil {
		// 정리 실패 시 finalizer 를 '남겨둔 채' 에러를 반환 → 재시도된다.
		// 이게 finalizer 의 안전장치다: 정리가 성공할 때까지 오브젝트가 사라지지 않는다.
		return ctrl.Result{}, fmt.Errorf("외부 리소스 정리 실패(재시도함): %w", err)
	}

	// 정리 성공 → finalizer 제거 → 이 Update 가 커밋되는 순간 API server 가 실제 삭제를 진행,
	// 이어서 owner reference 로 Deployment/Service 도 GC 된다.
	controllerutil.RemoveFinalizer(website, websiteFinalizer)
	if err := r.Update(ctx, website); err != nil {
		return ctrl.Result{}, fmt.Errorf("finalizer 제거 실패: %w", err)
	}
	log.Info("정리 완료, finalizer 제거 — 오브젝트 삭제 진행", "website", website.Name)
	return ctrl.Result{}, nil
}

// deprovisionExternalDNS 는 "외부 DNS 레코드 해제"를 시뮬레이션한다.
// 실제 환경에서는 외부 API 호출이 들어가며, 이 호출이 실패하면 에러를 반환해
// finalizer 가 유지되고 재시도된다(정리 보장).
func (r *WebsiteReconciler) deprovisionExternalDNS(ctx context.Context, website *webappv1.Website) error {
	logf.FromContext(ctx).Info("외부 DNS 레코드 해제(시뮬레이션)", "host", website.Spec.Host)
	r.event(website, corev1.EventTypeNormal, "ExternalCleanup",
		fmt.Sprintf("외부 DNS 레코드 해제: %s", website.Spec.Host))
	return nil
}

// updateStatus 는 관찰한 실제 상태를 status subresource 에 기록한다.
// 반드시 "바뀐 경우에만" 쓴다. status 쓰기도 Website 의 Update 이벤트를 유발하므로,
// 무조건 쓰면 reconcile → status write → reconcile → ... 무한 루프에 빠진다.
func (r *WebsiteReconciler) updateStatus(ctx context.Context, website *webappv1.Website) error {
	// 소유한 Deployment 의 현재 상태를 읽어 ReadyReplicas 를 가져온다.
	var deploy appsv1.Deployment
	if err := r.Get(ctx, client.ObjectKey{Name: website.Name, Namespace: website.Namespace}, &deploy); err != nil {
		if !apierrors.IsNotFound(err) {
			return err
		}
	}

	before := website.DeepCopy()

	website.Status.ObservedGeneration = website.Generation
	website.Status.ReadyReplicas = deploy.Status.ReadyReplicas

	ready := deploy.Status.ReadyReplicas >= website.Spec.Replicas && website.Spec.Replicas > 0
	switch {
	case website.Spec.Replicas == 0:
		website.Status.Phase = "Scaled-to-zero"
	case ready:
		website.Status.Phase = "Available"
	default:
		website.Status.Phase = "Progressing"
	}

	cond := metav1.Condition{
		Type:               typeAvailable,
		ObservedGeneration: website.Generation,
	}
	if ready {
		cond.Status = metav1.ConditionTrue
		cond.Reason = reasonReady
		cond.Message = "모든 복제본이 Ready 상태"
	} else {
		cond.Status = metav1.ConditionFalse
		cond.Reason = reasonNotReady
		cond.Message = fmt.Sprintf("Ready %d/%d", deploy.Status.ReadyReplicas, website.Spec.Replicas)
	}
	// SetStatusCondition 은 상태가 '실제로 바뀔 때만' LastTransitionTime 을 갱신한다
	// → DeepEqual 비교가 안정적으로 수렴한다.
	meta.SetStatusCondition(&website.Status.Conditions, cond)

	// 의미론적 비교: 바뀐 게 없으면 API 쓰기를 건너뛴다.
	if equality.Semantic.DeepEqual(before.Status, website.Status) {
		return nil
	}
	if err := r.Status().Update(ctx, website); err != nil {
		return fmt.Errorf("status 갱신 실패: %w", err)
	}
	return nil
}

func (r *WebsiteReconciler) event(obj *webappv1.Website, eventtype, reason, msg string) {
	if r.Recorder != nil {
		r.Recorder.Event(obj, eventtype, reason, msg)
	}
}

// labelsForWebsite 는 자식 리소스에 붙일 공통 라벨. recommended labels 규약을 따른다.
func labelsForWebsite(name string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":       "website",
		"app.kubernetes.io/instance":   name,
		"app.kubernetes.io/managed-by": "website-operator",
	}
}

// SetupWithManager 는 컨트롤러를 매니저에 등록하고 '무엇을 watch 할지' 선언한다.
//
//	For(&Website{})          — 주(primary) 리소스. 이 오브젝트의 이벤트로 reconcile 큐잉.
//	Owns(&Deployment{}/Service{}) — owner reference 가 Website 를 가리키는 자식의 이벤트를
//	                                주인(Website)의 reconcile 로 매핑한다. 누가 Deployment 를
//	                                손대도(또는 삭제해도) 우리가 즉시 되돌린다(self-healing).
func (r *WebsiteReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&webappv1.Website{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Named("website").
		Complete(r)
}
