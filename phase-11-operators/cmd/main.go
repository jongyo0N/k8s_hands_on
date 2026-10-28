/*
main.go — operator 바이너리의 진입점.

하는 일은 세 가지뿐이다:
  1) scheme 구성(어떤 Go 타입 ↔ 어떤 GVK 인지 등록)
  2) 매니저 생성(공유 cache·client·leader election·metrics/health 서버를 품는다)
  3) WebsiteReconciler 를 매니저에 붙이고 매니저를 Start

매니저가 제공하는 공유 cache(informer) 덕분에, 컨트롤러는 API server 를 매번 때리지 않고
로컬 캐시에서 읽는다. 이것이 대규모에서도 reconcile 가 싼 이유다.
*/
package main

import (
	"flag"
	"os"

	// 모든 client-go 인증 플러그인(GCP/Azure/OIDC 등)을 등록해, kubeconfig 의
	// exec/auth-provider 방식 자격증명으로도 클러스터에 붙을 수 있게 한다.
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	webappv1 "github.com/jongyo0N/k8s_hands_on/phase-11-operators/api/v1"
	"github.com/jongyo0N/k8s_hands_on/phase-11-operators/internal/controller"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	// 내장 타입(Deployment/Service/Pod 등) + 우리 Website 타입을 scheme 에 등록.
	// 등록하지 않은 타입은 클라이언트가 (역)직렬화하지 못한다.
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(webappv1.AddToScheme(scheme))
}

func main() {
	var metricsAddr string
	var probeAddr string
	var enableLeaderElection bool
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080",
		"metrics 엔드포인트가 바인딩할 주소. 운영에서는 TLS/인증을 붙여야 한다.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081",
		"health/ready probe 엔드포인트 주소.")
	flag.BoolVar(&enableLeaderElection, "leader-elect", false,
		"리더 선출 활성화. 복제본을 여러 개 띄워도 '한 번에 하나'만 reconcile 하게 한다.")
	opts := zap.Options{Development: true}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		// 리더 선출 lock 의 고유 ID. operator 마다 달라야 한다.
		LeaderElectionID: "website-operator.apps.example.com",
	})
	if err != nil {
		setupLog.Error(err, "매니저 생성 실패")
		os.Exit(1)
	}

	if err := (&controller.WebsiteReconciler{
		Client:   mgr.GetClient(),
		Scheme:   mgr.GetScheme(),
		Recorder: mgr.GetEventRecorderFor("website-controller"),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "컨트롤러 등록 실패", "controller", "Website")
		os.Exit(1)
	}

	// (d) validating/conversion webhook 을 붙인다면 여기서 SetupWebhookWithManager 를 호출한다.
	// webhook 은 강력하지만, 죽으면 관련 API 요청이 막혀 클러스터 장애로 번질 수 있다
	// → failurePolicy/timeout/namespaceSelector 설계가 필수(README 참고).

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "health check 등록 실패")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "ready check 등록 실패")
		os.Exit(1)
	}

	setupLog.Info("매니저 시작")
	// SetupSignalHandler 는 SIGTERM/SIGINT 를 받아 graceful shutdown 을 트리거한다.
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "매니저 실행 중 오류")
		os.Exit(1)
	}
}
