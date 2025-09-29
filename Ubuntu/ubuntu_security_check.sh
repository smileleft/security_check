#!/bin/bash

# 로그 파일 설정
LOG_FILE="./security_check_report_$(date +%Y%m%d_%H%M%S).log"
echo "==================================================" | tee -a "$LOG_FILE"
echo "  Ubuntu 24.04 기본 보안 점검 스크립트" | tee -a "$LOG_FILE"
echo "  실행 시간: $(date)" | tee -a "$LOG_FILE"
echo "  로그 파일: $LOG_FILE" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# root 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}오류: 이 스크립트는 root 권한으로 실행해야 합니다. (sudo 사용)${NC}"
    exit 1
fi

# ----------------------------------------------------
# 1. 불필요한 사용자 확인
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- 1. 사용자 계정 점검 ---" | tee -a "$LOG_FILE"

# 시스템 계정이 아닌 일반 사용자 목록 (UID 1000 이상)
ACTIVE_USERS=$(awk -F: '($3 >= 1000) {print $1}' /etc/passwd | grep -v 'nobody' | grep -v 'nfsnobody')

echo "  일반 사용자 목록 (UID 1000 이상, 시스템 계정 제외):" | tee -a "$LOG_FILE"
if [ -z "$ACTIVE_USERS" ]; then
    echo -e "  ${GREEN}[PASS]${NC} 추가된 일반 사용자 계정이 없습니다." | tee -a "$LOG_FILE"
else
    for user in $ACTIVE_USERS; do
        LAST_LOGIN=$(last -n 1 "$user" | head -n 1)
        # 30일 이상 로그인 기록이 없는 사용자 확인 (선택 사항)
        # 최근 로그인 기록만 출력
        echo "  - 사용자: ${user}, 최근 접속: ${LAST_LOGIN}" | tee -a "$LOG_FILE"
    done
    echo -e "  ${YELLOW}[INFO]${NC} 위 목록에서 불필요하거나 비활성화해야 할 계정이 있는지 수동으로 확인하십시오." | tee -a "$LOG_FILE"
fi

# UID가 0인 계정(root 권한) 확인 (root 외에 UID 0인 계정이 있으면 위험)
ROOT_ACCOUNTS=$(awk -F: '($3 == 0 && $1 != "root") {print $1}' /etc/passwd)
echo "" | tee -a "$LOG_FILE"
echo "  UID 0 (root 권한) 계정 (root 제외):" | tee -a "$LOG_FILE"
if [ -z "$ROOT_ACCOUNTS" ]; then
    echo -e "  ${GREEN}[PASS]${NC} root 외에 UID 0인 계정은 없습니다." | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} 다음과 같은 UID 0 계정이 발견되었습니다: $ROOT_ACCOUNTS" | tee -a "$LOG_FILE"
    echo -e "  ${RED}[ACTION]${NC} 이 계정들은 즉시 삭제하거나 UID를 변경해야 합니다." | tee -a "$LOG_FILE"
fi

# ----------------------------------------------------
# 2. 보안상 취약한 서비스 확인
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- 2. 활성화된 서비스 및 개방 포트 점검 ---" | tee -a "$LOG_FILE"

# 활성화된 네트워크 서비스 (LISTEN 상태 포트)
echo "  시스템에서 LISTEN 상태인 서비스 (TCP/UDP):" | tee -a "$LOG_FILE"
LISTENING_PORTS=$(ss -tuln)
echo "$LISTENING_PORTS" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"

# 주요 취약 서비스 확인 (Telnet, FTP, R-services 등)
INSECURE_SERVICES_CHECK=0
echo "  Telnet, R-services 등 취약 서비스 상태 확인:" | tee -a "$LOG_FILE"
if systemctl is-active telnetd 2>/dev/null | grep -q 'active'; then
    echo -e "  ${RED}[FAIL]${NC} telnetd 서비스가 활성화되어 있습니다." | tee -a "$LOG_FILE"
    INSECURE_SERVICES_CHECK=1
fi

if systemctl is-active rsh-server 2>/dev/null | grep -q 'active'; then
    echo -e "  ${RED}[FAIL]${NC} rsh-server 서비스가 활성화되어 있습니다." | tee -a "$LOG_FILE"
    INSECURE_SERVICES_CHECK=1
fi

if ! systemctl is-active sshd 2>/dev/null | grep -q 'active'; then
    echo -e "  ${YELLOW}[INFO]${NC} sshd 서비스가 비활성화되어 있습니다. 원격 접속이 필요한지 확인하십시오." | tee -a "$LOG_FILE"
fi

if [ "$INSECURE_SERVICES_CHECK" -eq 0 ]; then
    echo -e "  ${GREEN}[PASS]${NC} 알려진 주요 취약 서비스 (telnetd, rsh-server)는 활성화되어 있지 않습니다." | tee -a "$LOG_FILE"
fi

echo -e "  ${YELLOW}[INFO]${NC} 위의 LISTEN 포트 목록을 검토하여 불필요한 서비스가 외부로 노출되지 않았는지 확인하십시오." | tee -a "$LOG_FILE"

# ----------------------------------------------------
# 3. Sticky bit가 설정된 파일 확인
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- 3. Sticky Bit가 설정된 디렉터리 확인 ---" | tee -a "$LOG_FILE"

# 널리 알려진 안전한 Sticky Bit 설정 디렉터리 (주로 /tmp)
SAFE_STICKY_DIRS=('/tmp' '/var/tmp')
STICKY_BIT_FOUND=$(find / -type d -perm /+t 2>/dev/null | grep -v -E "$(IFS="|"; echo "${SAFE_STICKY_DIRS[*]}")")

if [ -z "$STICKY_BIT_FOUND" ]; then
    echo -e "  ${GREEN}[PASS]${NC} 기본 안전 디렉터리 외에 Sticky Bit가 설정된 디렉터리는 발견되지 않았습니다." | tee -a "$LOG_FILE"
else
    echo "  ${YELLOW}[INFO]${NC} 다음 경로에 Sticky Bit가 설정된 디렉터리가 발견되었습니다 (일반적인 경로 외):" | tee -a "$LOG_FILE"
    echo "$STICKY_BIT_FOUND" | tee -a "$LOG_FILE"
    echo -e "  ${RED}[ACTION]${NC} 해당 디렉터리가 Sticky Bit(다른 사용자의 파일 삭제 방지)가 필요한지 확인하십시오. 불필요하다면 제거해야 합니다." | tee -a "$LOG_FILE"
fi

# ----------------------------------------------------
# 4. 그 외 널리 알려진 보안 취약점 점검
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- 4. 기타 보안 설정 점검 ---" | tee -a "$LOG_FILE"

## 4-1. 패스워드 없는 sudo 사용자 확인
echo "  4-1. 패스워드 없는 sudo 사용자 확인:" | tee -a "$LOG_FILE"
NOPASSWD_SUDO=$(grep -r 'NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null)
if [ -z "$NOPASSWD_SUDO" ]; then
    echo -e "  ${GREEN}[PASS]${NC} sudo 설정에서 NOPASSWD가 명시적으로 설정된 항목이 발견되지 않았습니다." | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} NOPASSWD가 설정된 항목이 발견되었습니다. (권한 상승 위험):" | tee -a "$LOG_FILE"
    echo "$NOPASSWD_SUDO" | tee -a "$LOG_FILE"
fi

## 4-2. 시스템 업데이트 상태 확인
echo "" | tee -a "$LOG_FILE"
echo "  4-2. 시스템 업데이트 상태 확인:" | tee -a "$LOG_FILE"
if apt update -qq 2>/dev/null && apt list --upgradable 2>/dev/null | grep -q 'upgradable'; then
    echo -e "  ${YELLOW}[INFO]${NC} 업데이트 가능한 패키지가 있습니다. 즉시 ${RED}sudo apt upgrade${NC}를 실행하십시오." | tee -a "$LOG_FILE"
else
    echo -e "  ${GREEN}[PASS]${NC} 현재 업데이트할 패키지가 없거나 확인에 실패했습니다." | tee -a "$LOG_FILE"
fi

## 4-3. 핵심 파일 권한 점검 (/etc/passwd, /etc/shadow)
echo "" | tee -a "$LOG_FILE"
echo "  4-3. 핵심 파일 권한 점검 (/etc/passwd, /etc/shadow):" | tee -a "$LOG_FILE"
PASSWD_PERM=$(stat -c "%a %n" /etc/passwd)
SHADOW_PERM=$(stat -c "%a %n" /etc/shadow)

echo "  /etc/passwd 권한: $PASSWD_PERM" | tee -a "$LOG_FILE"
if [[ "$PASSWD_PERM" =~ ^644 ]]; then
    echo -e "  ${GREEN}[PASS]${NC} /etc/passwd 권한이 양호합니다 (644 권장)." | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} /etc/passwd 권한이 644보다 높거나 다릅니다. 확인이 필요합니다." | tee -a "$LOG_FILE"
fi

echo "  /etc/shadow 권한: $SHADOW_PERM" | tee -a "$LOG_FILE"
if [[ "$SHADOW_PERM" =~ ^000 || "$SHADOW_PERM" =~ ^400 ]]; then # 000 또는 400(최소) 권장
    echo -e "  ${GREEN}[PASS]${NC} /etc/shadow 권한이 양호합니다 (000 또는 400 권장)." | tee -a "$LOG_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} /etc/shadow 권한이 양호하지 않습니다. ${RED}000 또는 400${NC}이 권장됩니다." | tee -a "$LOG_FILE"
fi

## 4-4. 루트 계정 원격 SSH 접속 설정 확인
echo "" | tee -a "$LOG_FILE"
echo "  4-4. SSH 루트 계정 원격 접속 설정 확인:" | tee -a "$LOG_FILE"
SSHD_CONFIG_ROOT_LOGIN=$(grep -i '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')

if [ "$SSHD_CONFIG_ROOT_LOGIN" == "no" ]; then
    echo -e "  ${GREEN}[PASS]${NC} SSH 루트 접속이 차단되어 있습니다 (PermitRootLogin no)." | tee -a "$LOG_FILE"
else
    echo -e "  ${YELLOW}[INFO]${NC} SSH 루트 접속 설정 상태: $SSHD_CONFIG_ROOT_LOGIN" | tee -a "$LOG_FILE"
    echo -e "  ${RED}[FAIL]${NC} 루트 계정으로의 직접 SSH 접속은 보안상 매우 취약합니다. PermitRootLogin을 no로 설정하십시오." | tee -a "$LOG_FILE"
fi

# ----------------------------------------------------
# 점검 완료
# ----------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
echo "  보안 점검이 완료되었습니다." | tee -a "$LOG_FILE"
echo "  자세한 내용은 ${LOG_FILE} 파일을 참조하십시오." | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
