#!/bin/bash

# =================================================================
# EKS 클러스터 상태 및 보안 취약점 점검 스크립트
# 요구사항: AWS CLI, kubectl, jq 설치 필요
# =================================================================

# 설정 변수
CLUSTER_NAME="YOUR_EKS_CLUSTER_NAME" # << 여기에 클러스터 이름 입력
REGION="YOUR_AWS_REGION"             # << 여기에 AWS 리전 입력
LOG_FILE="./eks_audit_report_$(date +%Y%m%d_%H%M%S).log"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ----------------------------------------------------
# 0. 필수 도구 확인 및 초기 설정
# ----------------------------------------------------
echo "==================================================" | tee -a "$LOG_FILE"
echo -e "${BLUE}0. 초기 설정 및 도구 확인${NC}" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# 필수 도구 확인
for cmd in aws kubectl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}오류: $cmd 명령어를 찾을 수 없습니다. 설치해 주십시오.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# AWS 자격 증명 확인
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}오류: AWS 자격 증명이 유효하지 않거나 설정되지 않았습니다.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# kubectl 클러스터 설정 업데이트
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}오류: EKS 클러스터 ($CLUSTER_NAME)에 접근할 수 없습니다. 클러스터 이름 또는 리전을 확인하세요.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

echo -e "${GREEN}[PASS]${NC} 초기 설정 및 클러스터 연결 완료." | tee -a "$LOG_FILE"

# ----------------------------------------------------
# 1. 클러스터 상태 및 AWS 통합 점검 (AWS API/CLI)
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
echo -e "${BLUE}1. 클러스터 상태 및 AWS 통합 점검${NC}" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# 1-1. EKS 클러스터 상태 확인
CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.status" --output text 2>/dev/null)
echo "1-1. 클러스터 상태:" | tee -a "$LOG_FILE"
if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo -e "  ${GREEN}[PASS]${NC} EKS 클러스터 상태: ${CLUSTER_STATUS}" | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} EKS 클러스터 상태: ${CLUSTER_STATUS} (점검 필요)" | tee -a "$LOG_FILE"
fi

# 1-2. Kubernetes 버전 및 지원 종료 여부 확인
K8S_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.version" --output text 2>/dev/null)
echo "1-2. Kubernetes 버전:" | tee -a "$LOG_FILE"
echo -e "  ${YELLOW}[INFO]${NC} 버전: ${K8S_VERSION}. 최신 또는 지원 중인 버전인지 확인하십시오." | tee -a "$LOG_FILE"

# 1-3. 컨트롤 플레인 로깅 활성화 여부 확인
CONTROL_PLANE_LOGGING=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.logging.clusterLogging[0].enabled" --output text 2>/dev/null)
echo "1-3. 컨트롤 플레인 로깅 상태:" | tee -a "$LOG_FILE"
if [ "$CONTROL_PLANE_LOGGING" == "True" ]; then
    echo -e "  ${GREEN}[PASS]${NC} 컨트롤 플레인 로깅이 활성화되어 있습니다." | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} 컨트롤 플레인 로깅이 비활성화되어 있습니다. 감사 및 보안을 위해 활성화하십시오." | tee -a "$LOG_FILE"
fi

# ----------------------------------------------------
# 2. 쿠버네티스 객체 및 취약점 점검 (kubectl)
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
echo -e "${BLUE}2. 쿠버네티스 객체 및 취약점 점검${NC}" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# 2-1. 모든 네임스페이스에 대한 파드 상태 확인 (CrashLoopBackOff 등)
echo "2-1. 모든 네임스페이스의 비정상 파드 상태:" | tee -a "$LOG_FILE"
UNHEALTHY_PODS=$(kubectl get pods --all-namespaces -o wide | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff|Pending')
if [ -z "$UNHEALTHY_PODS" ]; then
    echo -e "  ${GREEN}[PASS]${NC} 비정상 상태의 파드가 발견되지 않았습니다." | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} 비정상 상태의 파드 발견 (로그 확인 필요):" | tee -a "$LOG_FILE"
    echo "$UNHEALTHY_PODS" | tee -a "$LOG_FILE"
fi

# 2-2. 특권(Privileged) 컨테이너 확인
echo "2-2. 'privileged: true'로 설정된 파드 확인:" | tee -a "$LOG_FILE"
PRIVILEGED_PODS=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[].securityContext.privileged == true) | .metadata.namespace + "/" + .metadata.name')
if [ -z "$PRIVILEGED_PODS" ]; then
    echo -e "  ${GREEN}[PASS]${NC} 특권 모드로 실행되는 파드가 발견되지 않았습니다." | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} 특권 모드로 실행되는 파드 발견 (점검 필요):" | tee -a "$LOG_FILE"
    echo "$PRIVILEGED_PODS" | tee -a "$LOG_FILE"
fi

# 2-3. 기본(Default) 서비스 계정 사용 여부 (보안 위험)
echo "2-3. 'default' 서비스 계정을 사용하는 파드 확인 (토큰 마운트 방지 권장):" | tee -a "$LOG_FILE"
DEFAULT_SA_PODS=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.serviceAccountName == "default") | .metadata.namespace + "/" + .metadata.name')
if [ -z "$DEFAULT_SA_PODS" ]; then
    echo -e "  ${GREEN}[PASS]${NC} 'default' 서비스 계정을 사용하는 파드가 없습니다." | tee -a "$LOG_FILE"
else
    echo -e "  ${YELLOW}[INFO]${NC} 'default' 서비스 계정을 사용하는 파드 발견:" | tee -a "$LOG_FILE"
    echo "$DEFAULT_SA_PODS" | tee -a "$LOG_FILE"
fi

# ----------------------------------------------------
# 3. CIS 벤치마크 기반 보안 점검 (Kube-bench)
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
echo -e "${BLUE}3. CIS 벤치마크 기반 보안 점검 (Kube-bench)${NC}" | tee -a "$LOG_FILE"
echo "  [INFO] Kube-bench는 클러스터 내부에 Job으로 배포하여 실행해야 합니다." | tee -a "$LOG_FILE"
echo "  [ACTION] 다음은 Kube-bench를 Job으로 실행하는 예시입니다." | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

KUBE_BENCH_MANIFEST="
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench
  namespace: kube-system
spec:
  template:
    spec:
      hostPID: true
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: [\"kube-bench\", \"run\"]
        volumeMounts:
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
        - name: etc-systemd
          mountPath: /etc/systemd
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
      restartPolicy: Never
      volumes:
      - name: var-lib-kubelet
        hostPath:
          path: /var/lib/kubelet
      - name: etc-systemd
        hostPath:
          path: /etc/systemd
      - name: etc-kubernetes
        hostPath:
          path: /etc/kubernetes
"

# Kube-bench Job 생성 및 실행
echo "$KUBE_BENCH_MANIFEST" | kubectl apply -f - > /dev/null 2>&1
echo -e "  ${YELLOW}[INFO]${NC} Kube-bench Job (kube-bench)을 kube-system 네임스페이스에 생성했습니다." | tee -a "$LOG_FILE"
echo -e "  ${YELLOW}[ACTION]${NC} 잠시 후 다음 명령어로 결과를 확인하십시오:" | tee -a "$LOG_FILE"
echo "  kubectl logs -n kube-system \$(kubectl get pods -n kube-system -l job-name=kube-bench -o jsonpath='{.items[0].metadata.name}')" | tee -a "$LOG_FILE"

# ----------------------------------------------------
# 점검 완료
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
echo "  EKS 보안 점검 스크립트 실행 완료." | tee -a "$LOG_FILE"
echo "  자세한 내용은 ${LOG_FILE} 파일을 참조하십시오." | tee -a "$LOG_FILE"
echo "  Kube-bench 결과를 별도로 확인하십시오." | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
