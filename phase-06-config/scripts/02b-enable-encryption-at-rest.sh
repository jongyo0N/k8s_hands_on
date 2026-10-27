#!/usr/bin/env bash
# Phase 6 / lab 2 (고급·파괴적) — encryption at rest 켜기 → 재암호화 → etcd 재확인
#
# ⚠️ 이 스크립트는 kube-apiserver static pod 매니페스트를 '직접 수정'한다(파괴적).
#    - 반드시 '실습 전용' kind 클러스터에서만 실행.
#    - 잘못되면 API server가 안 뜰 수 있다. 원본은 *.bak 으로 백업하고, 롤백 안내를 맨 아래 둔다.
#    - 가장 안전한 되돌리기: Phase 0 99-cleanup.sh로 클러스터를 지우고 새로 만드는 것.
#
# 실행: bash phase-06-config/scripts/02b-enable-encryption-at-rest.sh
#   provider 선택: PROVIDER=secretbox bash phase-06-config/scripts/02b-...   (기본 aescbc)
set -euo pipefail

CTX="kind-k8s-mastery"
NS="phase-06"
CP="k8s-mastery-control-plane"
PROVIDER="${PROVIDER:-aescbc}"   # aescbc | secretbox
K="kubectl --context ${CTX}"

ENC_DIR_NODE="/etc/kubernetes/enc"
ENC_FILE_NODE="${ENC_DIR_NODE}/encryption-config.yaml"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"

echo "==> 0) 사전 점검"
docker ps --filter "name=${CP}" --format '{{.Names}}' | grep -qx "${CP}" || { echo "[에러] ${CP} 없음"; exit 1; }
case "${PROVIDER}" in
  aescbc|secretbox) ;;
  *) echo "[에러] PROVIDER는 aescbc 또는 secretbox 만 지원"; exit 1 ;;
esac
command -v ruby >/dev/null 2>&1 || { echo "[에러] ruby 필요(매니페스트 YAML 편집용). macOS 기본 포함."; exit 1; }
echo "    provider=${PROVIDER}"

echo
echo "==> 1) 32바이트 랜덤 키 생성 + EncryptionConfiguration을 control-plane 노드에 기록"
KEY_B64="$(head -c 32 /dev/urandom | base64)"
docker exec "${CP}" mkdir -p "${ENC_DIR_NODE}"
# 실제 키로 채운 설정 파일을 노드에만 기록(git 아님). manifests/02-.../encryption-config.*.yaml 는 placeholder 버전.
docker exec -i "${CP}" tee "${ENC_FILE_NODE}" >/dev/null <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - ${PROVIDER}:
          keys:
            - name: key1
              secret: ${KEY_B64}
      - identity: {}
EOF
echo "    기록: ${CP}:${ENC_FILE_NODE} (provider=${PROVIDER}, key 이름=key1)"

echo
echo "==> 2) kube-apiserver static pod 매니페스트 패치 (--encryption-provider-config 플래그 + hostPath 볼륨)"
docker exec "${CP}" test -f "${APISERVER_MANIFEST}.bak" || docker exec "${CP}" cp "${APISERVER_MANIFEST}" "${APISERVER_MANIFEST}.bak"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
docker cp "${CP}:${APISERVER_MANIFEST}" "${TMP}/kube-apiserver.yaml"

# Ruby(psych)로 안전하게 편집 — 멱등(이미 있으면 중복 추가 안 함).
ENC_FLAG="--encryption-provider-config=${ENC_FILE_NODE}" ENC_DIR="${ENC_DIR_NODE}" \
ruby -ryaml -e '
  f = ARGV[0]
  doc = YAML.load_file(f)
  c = doc["spec"]["containers"][0]
  c["command"] ||= []
  unless c["command"].any? { |x| x.to_s.start_with?("--encryption-provider-config=") }
    c["command"] << ENV["ENC_FLAG"]
  end
  dir = ENV["ENC_DIR"]
  c["volumeMounts"] ||= []
  unless c["volumeMounts"].any? { |m| m["mountPath"] == dir }
    c["volumeMounts"] << { "name" => "enc", "mountPath" => dir, "readOnly" => true }
  end
  doc["spec"]["volumes"] ||= []
  unless doc["spec"]["volumes"].any? { |v| v["name"] == "enc" }
    doc["spec"]["volumes"] << { "name" => "enc", "hostPath" => { "path" => dir, "type" => "DirectoryOrCreate" } }
  end
  File.write(f, YAML.dump(doc))
' "${TMP}/kube-apiserver.yaml"

docker cp "${TMP}/kube-apiserver.yaml" "${CP}:${APISERVER_MANIFEST}"
echo "    패치 완료 (원본 백업: ${APISERVER_MANIFEST}.bak)"

echo
echo "==> 3) kubelet이 apiserver를 재기동할 때까지 대기 (잠깐 API 끊김은 정상)"
printf "    "
ok=0
for _ in $(seq 1 90); do
  if ${K} get --raw='/readyz' >/dev/null 2>&1; then printf " ready!\n"; ok=1; break; fi
  printf "."; sleep 2
done
[ "${ok}" = "1" ] || { echo; echo "[경고] apiserver가 제때 안 떴다. 롤백 안내(맨 아래) 참고."; exit 1; }

echo
echo "==> 4) 기존 Secret 재암호화: 평문으로 저장돼 있던 것을 다시 써서 ${PROVIDER}로 암호화"
echo "    (identity provider 덕분에 평문도 읽히고, replace로 재저장하면 첫 provider로 암호화됨)"
${K} get secrets -A -o json | ${K} replace -f - >/dev/null
echo "    완료."

echo
echo "==> 5) etcd에서 재확인 — 이제 암호문이어야 한다"
eid="$(docker exec "${CP}" crictl ps --name etcd --state Running -q 2>/dev/null | head -1)"
docker exec "${CP}" crictl exec "${eid}" etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get "/registry/secrets/${NS}/demo-plain" | hexdump -C | head -20

cat <<EOF

    해석:
      - 값 앞에 'k8s:enc:${PROVIDER}:v1:key1:' 접두어 + 그 뒤로 '읽을 수 없는 바이트'가 보인다.
      - 02에서 보이던 평문(super-secret-password-123)이 더는 안 보인다 → encryption at rest 성공.
      - 단, 키(key1)는 여전히 노드 ${ENC_FILE_NODE} 에 '평문'으로 있다.
        → 진짜 프로덕션은 KMS v2 provider로 KEK를 외부 KMS에 두고, etcd엔 암호화된 DEK만 둔다.

    ── 롤백(암호화 끄기, 실습 뒤) ───────────────────────────────────────────────
      순서가 중요하다. 설정만 지우면 apiserver가 기존 암호문을 '복호화 못 해' Secret을 못 읽는다.
      1) ${ENC_FILE_NODE} 에서 providers 순서를 identity가 맨 앞이 되도록 바꾼다(= 쓰기를 평문으로).
         apiserver 재기동 대기 후:  kubectl get secrets -A -o json | kubectl replace -f -   (평문화)
      2) 그 다음에야 매니페스트 복구: docker exec ${CP} cp ${APISERVER_MANIFEST}.bak ${APISERVER_MANIFEST}
      * 번거로우면 Phase 0 99-cleanup.sh로 클러스터를 지우고 새로 만드는 게 제일 깔끔하다.
EOF
