#!/bin/bash

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 輔助函數
print_section() {
    echo -e "${BLUE}========== $1 ==========${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

# 使用固定的 IP 地址列表
get_host_ips() {
    print_section "使用固定 IP 列表"
    
    # 直接使用固定的 IP 列表
    IPS="10.6.6.32 10.6.4.213 10.6.4.214 10.6.4.215 10.6.4.217 10.6.4.218 10.6.4.219 10.6.4.220 10.6.4.224 10.6.4.234"
    
    print_success "已設定主機 IP 列表"
    echo "$IPS"
}

# 設置一般使用者的 SSH 金鑰
setup_user_ssh() {
    print_section "設置一般使用者的 SSH 金鑰"
    
    # 檢查是否已經生成過 SSH 金鑰
    if [ ! -f ~/.ssh/id_rsa ]; then
        print_warning "未找到 SSH 金鑰，將生成新的金鑰"
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
        print_success "已生成 SSH 金鑰"
    else
        print_success "SSH 金鑰已存在"
    fi
    
    # 取得主機 IP 列表
    IPS=$(get_host_ips)
    
    # 將 SSH 公鑰複製到每個節點
    for ip in $IPS; do
        print_section "複製 SSH 金鑰到 $ip (使用者: $USER)"
        sshpass -p "nmuq*kQy7NGKPA6V711Va" ssh-copy-id -o StrictHostKeyChecking=no $USER@$ip
        
        if [ $? -eq 0 ]; then
            print_success "已成功複製 SSH 金鑰到 $ip"
            # 測試 SSH 連接
            ssh -o BatchMode=yes -o ConnectTimeout=5 $USER@$ip "echo SSH 連接測試成功"
            if [ $? -eq 0 ]; then
                print_success "SSH 連接測試成功: $ip"
            else
                print_error "SSH 連接測試失敗: $ip"
            fi
        else
            print_error "複製 SSH 金鑰到 $ip 失敗"
        fi
    done
}

# 設置 root 使用者的 SSH 金鑰
setup_root_ssh() {
    print_section "設置 root 使用者的 SSH 金鑰"
    
    print_warning "請注意：接下來將切換到 root 用戶執行操作，需要輸入 sudo 密碼"
    print_warning "如果出現密碼提示，請輸入您的 sudo 密碼"
    
    # 獲取 IP 列表，傳遞給 root 腳本
    IPS=$(get_host_ips)
    
    # 創建臨時腳本並使用 sudo 執行
    ROOT_SCRIPT=$(mktemp)
    
    cat > $ROOT_SCRIPT << EOF
#!/bin/bash
# 顏色定義
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

# 輔助函數
print_section() {
    echo -e "\${BLUE}========== \$1 ==========\${NC}"
}

print_success() {
    echo -e "\${GREEN}✓ \$1\${NC}"
}

print_error() {
    echo -e "\${RED}✗ \$1\${NC}"
}

# 確保 .ssh 目錄存在且權限正確
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 檢查是否已經生成過 SSH 金鑰
if [ ! -f /root/.ssh/id_rsa ]; then
    echo -e "\${YELLOW}未找到 root SSH 金鑰，將生成新的金鑰\${NC}"
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
    echo -e "\${GREEN}已生成 root SSH 金鑰\${NC}"
else
    echo -e "\${GREEN}root SSH 金鑰已存在\${NC}"
fi

# IP 列表
IPS="$IPS"

# 將 root SSH 公鑰複製到每個節點
for ip in \$IPS; do
    print_section "複製 root SSH 金鑰到 \$ip"
    
    # 確保 known_hosts 不會阻止連接
    ssh-keyscan -H \$ip >> /root/.ssh/known_hosts 2>/dev/null
    
    # 使用 sshpass 複製金鑰
    sshpass -p "nmuq*kQy7NGKPA6V711Va" ssh-copy-id -o StrictHostKeyChecking=no root@\$ip
    
    if [ \$? -eq 0 ]; then
        print_success "已成功複製 root SSH 金鑰到 \$ip"
        # 測試 SSH 連接
        ssh -o BatchMode=yes -o ConnectTimeout=5 root@\$ip "echo Root SSH 連接測試成功"
        if [ \$? -eq 0 ]; then
            print_success "root SSH 連接測試成功: \$ip"
        else
            print_error "root SSH 連接測試失敗: \$ip"
        fi
    else
        print_error "複製 root SSH 金鑰到 \$ip 失敗"
    fi
done
EOF

    # 設置腳本權限
    chmod +x $ROOT_SCRIPT
    
    # 使用 sudo 執行腳本
    sudo bash $ROOT_SCRIPT
    
    # 清理臨時腳本
    rm -f $ROOT_SCRIPT
}

# 檢查是否安裝了 sshpass
check_sshpass() {
    print_section "檢查 sshpass"
    
    if ! command -v sshpass &> /dev/null; then
        print_warning "sshpass 未安裝，嘗試安裝"
        
        # 檢測系統類型
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y sshpass
        elif command -v yum &> /dev/null; then
            sudo yum install -y sshpass
        elif command -v brew &> /dev/null; then
            brew install sshpass
        else
            print_error "無法安裝 sshpass，請手動安裝後再運行此腳本"
            exit 1
        fi
        
        if command -v sshpass &> /dev/null; then
            print_success "sshpass 安裝成功"
        else
            print_error "sshpass 安裝失敗，請手動安裝後再運行此腳本"
            exit 1
        fi
    else
        print_success "sshpass 已安裝"
    fi
}

# 主函數
main() {
    print_section "SSH 金鑰設置腳本"
    
    # 檢查 sshpass
    check_sshpass
    
    # 設置一般使用者的 SSH 金鑰
    setup_user_ssh
    
    # 設置 root 使用者的 SSH 金鑰
    setup_root_ssh
    
    print_section "SSH 金鑰設置完成"
    print_success "一般使用者和 root 使用者的 SSH 金鑰已設置完成"
}

# 執行主函數
main 