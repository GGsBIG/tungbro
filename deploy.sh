#!/bin/bash

# Harbor 與 Kubernetes 叢集自動化部署腳本

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

# 檢查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 命令未找到，請先安裝"
        exit 1
    fi
}

# 設置 SSH 金鑰認證
setup_ssh_keys() {
    print_section "設置 SSH 金鑰認證"
    
    # 檢查是否已經生成過 SSH 金鑰
    if [ ! -f ~/.ssh/id_rsa ]; then
        print_warning "未找到 SSH 金鑰，將生成新的金鑰"
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
        print_success "已生成 SSH 金鑰"
    else
        print_success "SSH 金鑰已存在"
    fi
    
    # 從 inventory.ini 提取主機
    echo "正在從 inventory.ini 讀取主機列表..."
    
    # 使用 awk 從 inventory 文件中提取 IP 地址
    hosts=$(awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}' inventory.ini)
    
    if [ -z "$hosts" ]; then
        print_error "無法從 inventory.ini 中讀取主機"
        return 1
    fi
    
    # 預設使用者和密碼
    default_user="gravity"
    default_password="nmuq*kQy7NGKPA6V711Va"
    
    # 提示用戶輸入認證信息
    read -p "請輸入目標主機的使用者名稱 [默認: $default_user]: " username
    username=${username:-$default_user}
    
    read -s -p "請輸入目標主機的密碼 [默認: $default_password]: " password
    echo ""
    password=${password:-$default_password}
    
    # 為所有主機設置 SSH 金鑰認證
    for host in $hosts; do
        echo "正在設置 $host 的 SSH 金鑰認證..."
        # 檢查是否可以 ping 通主機
        if ping -c 1 -W 2 $host &> /dev/null; then
            # 使用 sshpass 複製公鑰到遠程主機
            if command -v sshpass &> /dev/null; then
                sshpass -p "$password" ssh-copy-id -o StrictHostKeyChecking=no -f $username@$host
            else
                print_warning "未安裝 sshpass，將嘗試手動設置 SSH 金鑰"
                cat ~/.ssh/id_rsa.pub | ssh -o StrictHostKeyChecking=no $username@$host "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
            fi
            
            if [ $? -eq 0 ]; then
                print_success "已成功設置 $host 的 SSH 金鑰認證"
            else
                print_error "無法設置 $host 的 SSH 金鑰認證，請手動檢查"
            fi
        else
            print_error "無法 ping 通 $host，請檢查網絡連接"
        fi
    done
    
    print_success "SSH 金鑰設置完成"
}

# 檢查主機連接性
check_hosts_connectivity() {
    print_section "檢查主機連接性"
    
    # 從 inventory.ini 提取主機
    hosts=$(awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}' inventory.ini)
    
    local all_reachable=true
    
    for host in $hosts; do
        echo "檢查 $host 連接性..."
        
        # 檢查是否可以 ping 通主機
        if ping -c 1 -W 2 $host &> /dev/null; then
            print_success "$host 可以 ping 通"
            
            # 嘗試 SSH 連接
            ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no gravity@$host "echo 2>&1" &> /dev/null
            
            if [ $? -eq 0 ]; then
                print_success "$host SSH 連接成功"
            else
                print_error "$host SSH 連接失敗，請檢查 SSH 配置"
                all_reachable=false
            fi
        else
            print_error "$host 無法 ping 通，請檢查網絡連接或防火牆設置"
            all_reachable=false
        fi
    done
    
    if [ "$all_reachable" = false ]; then
        print_warning "部分主機無法連接，這可能會導致部署失敗。是否繼續？(y/n)"
        read -p "> " continue_deploy
        
        if [[ $continue_deploy != "y" && $continue_deploy != "Y" ]]; then
            print_error "部署已取消"
            exit 1
        fi
    else
        print_success "所有主機都可以連接"
    fi
}

# 檢查環境
check_environment() {
    print_section "檢查環境"
    
    check_command ansible
    check_command ansible-playbook
    
    # 檢查 inventory 文件
    if [ ! -f "inventory.ini" ]; then
        print_error "inventory.ini 文件不存在"
        exit 1
    fi
    
    # 檢查 playbooks 目錄
    if [ ! -d "playbooks" ]; then
        print_error "playbooks 目錄不存在"
        exit 1
    fi
    
    # 檢查 templates 目錄
    if [ ! -d "templates" ]; then
        print_warning "templates 目錄不存在，將創建"
        mkdir -p templates
    fi
    
    # 檢查並安裝必要的工具
    if ! command -v sshpass &> /dev/null; then
        print_warning "sshpass 未安裝，將嘗試安裝"
        sudo apt-get update && sudo apt-get install -y sshpass
        if [ $? -eq 0 ]; then
            print_success "sshpass 安裝成功"
        else
            print_warning "sshpass 安裝失敗，但不影響部署"
        fi
    fi
}

# 創建必要的模板文件
create_templates() {
    print_section "創建必要的模板文件"
    
    # 創建 harbor.yml.j2 模板
    if [ ! -f "templates/harbor.yml.j2" ]; then
        cat > templates/harbor.yml.j2 << 'EOF'
# Configuration file of Harbor

# The IP address or hostname to access admin UI and registry service.
hostname: {{ harbor_domain }}

# http related config
http:
  port: 80

# https related config
https:
  port: {{ harbor_https_port }}
  certificate: {{ harbor_cert_dir }}/harbor.crt
  private_key: {{ harbor_cert_dir }}/harbor.key

# The initial password of Harbor admin
harbor_admin_password: {{ harbor_admin_password }}

# Harbor DB configuration
database:
  password: root123
  max_idle_conns: 50
  max_open_conns: 100

# The default data volume
data_volume: {{ harbor_data_dir }}

# Log configurations
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: {{ harbor_data_dir }}/log

# Enable chartmuseum
chartmuseum:
  enabled: true

# Trivy configuration
trivy:
  enabled: true
  ignore_unfixed: false
  insecure: false

_version: 2.10.0
EOF
        print_success "創建 harbor.yml.j2 模板"
    else
        print_success "harbor.yml.j2 模板已存在"
    fi

    # 創建 harbor.service.j2 模板
    if [ ! -f "templates/harbor.service.j2" ]; then
        cat > templates/harbor.service.j2 << 'EOF'
[Unit]
Description=Harbor Container Registry
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory={{ harbor_data_dir }}/install/harbor
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF
        print_success "創建 harbor.service.j2 模板"
    else
        print_success "harbor.service.j2 模板已存在"
    fi

    # 創建 openssl.cnf.j2 模板
    if [ ! -f "templates/openssl.cnf.j2" ]; then
        cat > templates/openssl.cnf.j2 << 'EOF'
[ req ]
default_bits = 2048
default_md = sha256
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[ req_distinguished_name ]
C = TW
ST = Taiwan
L = Taipei
O = BroBridge
OU = IT Department
CN = {{ harbor_domain }}

[ v3_req ]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = {{ harbor_domain }}
IP.1 = {{ harbor_hostname }}
EOF
        print_success "創建 openssl.cnf.j2 模板"
    else
        print_success "openssl.cnf.j2 模板已存在"
    fi

    # 創建 containerd-hosts.toml.j2 模板
    if [ ! -f "templates/containerd-hosts.toml.j2" ]; then
        cat > templates/containerd-hosts.toml.j2 << 'EOF'
server = "https://{{ harbor_domain }}"

[host."https://{{ harbor_domain }}"]
  ca = "/etc/containerd/certs.d/{{ harbor_domain }}/ca.crt"
EOF
        print_success "創建 containerd-hosts.toml.j2 模板"
    else
        print_success "containerd-hosts.toml.j2 模板已存在"
    fi

    # 創建 containerd-hosts-ip.toml.j2 模板
    if [ ! -f "templates/containerd-hosts-ip.toml.j2" ]; then
        cat > templates/containerd-hosts-ip.toml.j2 << 'EOF'
server = "https://{{ harbor_hostname }}"

[host."https://{{ harbor_hostname }}"]
  ca = "/etc/containerd/certs.d/{{ harbor_hostname }}/ca.crt"
EOF
        print_success "創建 containerd-hosts-ip.toml.j2 模板"
    else
        print_success "containerd-hosts-ip.toml.j2 模板已存在"
    fi

    # 創建 kubeadm-config.yaml.j2 模板
    if [ ! -f "templates/kubeadm-config.yaml.j2" ]; then
        cat > templates/kubeadm-config.yaml.j2 << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: {{ ansible_host }}
  bindPort: 6443
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: {{ k8s_version }}
controlPlaneEndpoint: "{{ k8s_control_plane_endpoint }}:6443"
networking:
  podSubnet: "{{ pod_network_cidr }}"
  serviceSubnet: "{{ service_network_cidr }}"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
        print_success "創建 kubeadm-config.yaml.j2 模板"
    else
        print_success "kubeadm-config.yaml.j2 模板已存在"
    fi
}

# 運行 Ansible playbook
run_playbook() {
    local playbook=$1
    local extra_args=$2
    
    print_section "運行 Playbook: $playbook"
    
    if [ -z "$extra_args" ]; then
        if [ -n "$SUDO_PASS" ]; then
            ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini "$playbook" --extra-vars "ansible_become_password=$SUDO_PASS"
        else
            ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini "$playbook" --ask-become-pass
        fi
    else
        if [ -n "$SUDO_PASS" ]; then
            ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini "$playbook" --extra-vars "ansible_become_password=$SUDO_PASS" $extra_args
        else
            ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini "$playbook" --ask-become-pass $extra_args
        fi
    fi
    
    if [ $? -ne 0 ]; then
        print_error "Playbook $playbook 運行失敗"
        return 1
    else
        print_success "Playbook $playbook 運行成功"
        return 0
    fi
}

# 部署 Kubernetes 和 Harbor
deploy_all() {
    print_section "開始部署 Kubernetes 和 Harbor"
    
    # 步驟 1: 測試節點連通性
    run_playbook playbooks/00-ping.yml || exit 1
    
    # 步驟 2: 系統準備工作
    run_playbook playbooks/01-prepare.yml || exit 1
    
    # 步驟 3: 安裝容器運行時
    run_playbook playbooks/02-install-runtime.yml || exit 1
    
    # 步驟 4: 安裝 Kubernetes 組件
    run_playbook playbooks/03-install-k8s.yml || exit 1
    
    # 步驟 5: 初始化 master 節點
    run_playbook playbooks/04-init-master.yml || exit 1
    
    # 步驟 6: 加入其他 master 和 worker 節點
    run_playbook playbooks/05-join-nodes.yml || exit 1
    
    # 步驟 7: 設置 CNI 網絡
    run_playbook playbooks/06-setup-cni.yml || exit 1
    
    # 步驟 8: 部署 NFS 服務器
    run_playbook playbooks/07-nfs-server.yml || exit 1
    
    # 步驟 9: 配置 NFS 客戶端
    run_playbook playbooks/08-nfs-client.yml || exit 1
    
    # 步驟 10: 部署 Harbor 容器倉庫
    if [ -n "$HARBOR_DOMAIN" ]; then
        run_playbook playbooks/09-harbor-deploy.yml "--extra-vars harbor_domain=$HARBOR_DOMAIN" || exit 1
    else
        run_playbook playbooks/09-harbor-deploy.yml || exit 1
    fi
    
    # 步驟 11: 部署 CDC (如果存在)
    if [ -f "playbooks/10-cdc.yml" ]; then
        run_playbook playbooks/10-cdc.yml || exit 1
    fi
    
    # 步驟 12: 部署附加組件 (如果存在)
    if [ -f "playbooks/11-addons.yml" ]; then
        run_playbook playbooks/11-addons.yml || exit 1
    fi
    
    print_section "部署完成"
    print_success "Kubernetes 和 Harbor 已成功部署"
    print_success "Harbor 可通過瀏覽器訪問: https://harbor.tungbro.com"
}

# 僅部署 Harbor
deploy_harbor() {
    print_section "僅部署 Harbor"
    
    # 如果提供了 Harbor 域名，則使用它
    if [ -n "$HARBOR_DOMAIN" ]; then
        run_playbook playbooks/09-harbor-deploy.yml "--extra-vars harbor_domain=$HARBOR_DOMAIN" || exit 1
    else
        run_playbook playbooks/09-harbor-deploy.yml || exit 1
    fi
    
    print_section "Harbor 部署完成"
    print_success "Harbor 已成功部署，可通過瀏覽器訪問: https://harbor.tungbro.com"
    print_success "使用 docker login harbor.tungbro.com 進行登入"
}

# 僅部署 NFS
deploy_nfs() {
    print_section "僅部署 NFS"
    
    run_playbook playbooks/07-nfs-server.yml || exit 1
    run_playbook playbooks/08-nfs-client.yml || exit 1
    
    print_section "NFS 部署完成"
}

# 顯示使用手冊
show_manual() {
    cat << 'MANUAL'
# Kubernetes 與 Harbor 部署使用手冊

## 系統要求
- 所有節點必須運行 Ubuntu 20.04 或更高版本
- 所有節點必須有足夠的資源（CPU、記憶體、磁碟空間）
- 所有節點之間必須能夠相互通信
- 所有節點必須能夠訪問互聯網（用於下載軟件包）

## 部署前準備
1. 確保已安裝 Ansible
   ```
   apt update && apt install -y ansible
   ```

2. 編輯 inventory.ini 文件，設置節點信息

## 部署步驟
1. 完整部署（Kubernetes + NFS + Harbor）
   ```
   ./deploy.sh --all
   ```

2. 僅部署 Harbor
   ```
   ./deploy.sh --only-harbor --harbor-domain harbor.example.com
   ```

3. 僅部署 NFS
   ```
   ./deploy.sh --only-nfs
   ```

## 部署後驗證
請參考 README.md 文件中的部署後驗證步驟。
MANUAL
}

# 主函數
main() {
    print_section "Kubernetes 與 Harbor 部署腳本"
    
    # 解析命令行參數
    SETUP_SSH=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sudo-pass)
                SUDO_PASS="$2"
                shift 2
                ;;
            --setup-ssh)
                SETUP_SSH=true
                shift
                ;;
            --only-nfs)
                ONLY_NFS=true
                shift
                ;;
            --only-harbor)
                ONLY_HARBOR=true
                shift
                ;;
            --harbor-domain)
                HARBOR_DOMAIN="$2"
                shift 2
                ;;
            --all)
                DEPLOY_ALL=true
                shift
                ;;
            --manual)
                SHOW_MANUAL=true
                shift
                ;;
            --help)
                echo "用法: $0 [選項]"
                echo "選項:"
                echo "  --sudo-pass PASSWORD    設置 sudo 密碼，避免交互式輸入"
                echo "  --setup-ssh             設置 SSH 金鑰認證（首次運行時使用）"
                echo "  --only-nfs              只部署 NFS"
                echo "  --only-harbor           只部署 Harbor"
                echo "  --harbor-domain DOMAIN  設置 Harbor 域名"
                echo "  --all                   部署全部組件（Kubernetes + NFS + Harbor）"
                echo "  --manual                顯示使用手冊"
                echo "  --help                  顯示此幫助信息"
                exit 0
                ;;
            *)
                print_error "未知選項: $1"
                exit 1
                ;;
        esac
    done
    
    # 檢查環境
    check_environment
    
    # 創建模板
    create_templates
    
    # 如果指定了設置 SSH，則執行 SSH 金鑰設置
    if [ "$SETUP_SSH" = true ]; then
        setup_ssh_keys
    fi
    
    # 檢查主機連接性
    check_hosts_connectivity
    
    # 顯示使用手冊
    if [ "$SHOW_MANUAL" = true ]; then
        show_manual
        exit 0
    fi
    
    # 運行部署
    if [ "$ONLY_NFS" = true ]; then
        deploy_nfs
    elif [ "$ONLY_HARBOR" = true ]; then
        deploy_harbor
    elif [ "$DEPLOY_ALL" = true ]; then
        deploy_all
    else
        print_warning "未指定部署選項，請使用 --all, --only-nfs 或 --only-harbor"
        echo "運行 $0 --help 查看幫助信息"
    fi
}

# 執行主函數
main "$@" 