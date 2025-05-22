# Kubernetes 與 Harbor 自動化部署系統

這個專案提供了一套完整的自動化部署腳本，用於快速建立生產就緒的 Kubernetes 叢集和 Harbor 容器倉庫，全部基於 Ansible 實現高度自動化。

## 系統功能

- ✅ 全自動部署多節點 Kubernetes 叢集（支持多主節點高可用配置）
- ✅ 自動配置 containerd 和 Docker 作為容器運行時
- ✅ 整合 Calico 網絡插件
- ✅ 自動部署和配置 NFS 服務器和客戶端
- ✅ 自動部署 Harbor 容器倉庫與TLS加密
- ✅ 自動設置節點標籤和容忍度
- ✅ CoreDNS 優化配置
- ✅ 支持 Ubuntu 20.04+ 環境

## 系統要求

- **主控端要求**:
  - 已安裝 Ansible (2.9+)
  - 已安裝 SSH 客戶端
  - 可選: sshpass（用於自動設置SSH密鑰）

- **節點要求**:
  - Ubuntu 20.04 或更高版本
  - 每個 Master 節點: 至少 2 CPU核心, 4GB RAM, 50GB 磁盤
  - 每個 Worker 節點: 至少 2 CPU核心, 4GB RAM, 50GB 磁盤
  - NFS 服務器: 至少 1 CPU核心, 2GB RAM, 100GB+ 磁盤
  - Harbor 節點: 至少 2 CPU核心, 4GB RAM, 100GB+ 磁盤
  - 所有節點之間可以相互通信（防火牆允許相關端口）
  - 所有節點可以訪問互聯網（用於下載軟件包）

## 目錄結構

```
./
├── deploy.sh                  # 主部署腳本
├── inventory.ini              # 節點清單配置文件
├── group_vars/                # 全局變量
│   └── all.yml                # 全局變量定義
├── playbooks/                 # Ansible playbook 文件
│   ├── 00-ping.yml            # 測試節點連通性
│   ├── 01-prepare.yml         # 系統準備工作
│   ├── 02-install-runtime.yml # 安裝容器運行時（含Docker和Containerd）
│   ├── 03-install-k8s.yml     # 安裝 Kubernetes 組件
│   ├── 04-init-master.yml     # 初始化 master 節點
│   ├── 05-join-nodes.yml      # 加入其他 master 和 worker 節點
│   ├── 06-setup-cni.yml       # 設置 CNI 網絡
│   ├── 07-nfs-server.yml      # 部署 NFS 服務器
│   ├── 08-nfs-client.yml      # 部署 NFS 客戶端
│   ├── 09-harbor-deploy.yml   # 部署 Harbor 容器倉庫
│   ├── 10-cdc.yml             # 部署 CDC（可選）
│   └── 11-addons.yml          # 部署附加組件（可選）
└── templates/                 # 配置模板文件
    ├── containerd-hosts-ip.toml.j2    # Containerd IP 配置模板
    ├── containerd-hosts.toml.j2       # Containerd 域名配置模板
    ├── coredns-toleration.yaml.j2     # CoreDNS 容忍度配置模板
    ├── gravity-cdc-config.yml.j2      # CDC 配置模板（可選）
    ├── gravity-cdc-docker-compose.yml.j2 # CDC Docker Compose 模板（可選）
    ├── harbor-full.yml.j2             # Harbor 完整配置模板
    ├── harbor.service.j2              # Harbor 服務模板
    ├── harbor.yml.j2                  # Harbor 基本配置模板
    ├── kubeadm-config.yaml.j2         # Kubeadm 配置模板
    └── openssl.cnf.j2                 # OpenSSL 配置模板
```

## 快速開始

### 基本配置

1. 克隆此儲存庫到您的部署機器
   ```bash
   git clone https://github.com/your-repo/tungbro-ansible.git
   cd tungbro-ansible
   ```

2. 修改 `inventory.ini` 文件，設置您的節點信息

   ```ini
   # 主節點組
   [masters]
   master-1 ansible_host=10.6.4.213
   master-2 ansible_host=10.6.4.214
   master-3 ansible_host=10.6.4.215

   # 工作節點組
   [workers]
   worker-1 ansible_host=10.6.4.216
   worker-2 ansible_host=10.6.4.217
   worker-3 ansible_host=10.6.4.218

   # NFS 服務器組
   [nfs]
   nfs-server ansible_host=10.6.4.220

   # Harbor 服務器組
   [harbor]
   harbor ansible_host=10.6.4.224

   # Kubernetes 叢集組（包含 masters 和 workers）
   [k8s_cluster:children]
   masters
   workers

   # 所有組
   [all:vars]
   ansible_user=gravity
   ansible_ssh_pass=nmuq*kQy7NGKPA6V711Va
   ansible_become=true
   ansible_become_pass=nmuq*kQy7NGKPA6V711Va
   ```

3. 調整 `group_vars/all.yml` 中的全局變量來自定義部署

   ```yaml
   # Kubernetes 版本設定
   kubernetes_version: "1.31.0"
   kubernetes_apt_release_channel: stable
   kubernetes_apt_repository: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /"

   # 網絡設定
   pod_network_cidr: "192.168.0.0/16"  # Calico 網絡 CIDR
   service_network_cidr: "10.96.0.0/12" # 服務網絡 CIDR

   # 控制平面設定
   k8s_control_plane_endpoint: "10.10.7.231" # 第一個 master 節點 IP 或負載均衡器 IP
   k8s_control_plane_port: "6443"
   
   # NFS 設定
   nfs_server: "10.10.7.237"  # NFS 服務器 IP
   nfs_export_dir: "/data/nfs" # NFS 導出目錄
   
   # Harbor 設定
   harbor_version: "2.10.0"
   harbor_domain: "harbor.tungbro.com" # Harbor 域名
   harbor_admin_password: "1qaz@WSX"   # Harbor 管理員密碼
   harbor_data_dir: "/data/harbor"     # Harbor 數據目錄
   ```

4. 確保部署腳本有執行權限

   ```bash
   chmod +x deploy.sh
   ```

### 部署選項

#### 完整一鍵部署（Kubernetes + NFS + Harbor）

```bash
./deploy.sh --all
```

#### 設置 SSH 金鑰（首次使用）

首次運行時，建議先設置 SSH 金鑰認證，簡化後續操作：

```bash
./deploy.sh --setup-ssh
```

#### 僅部署 Harbor 容器倉庫

```bash
# 使用默認域名
./deploy.sh --only-harbor 

# 指定自定義域名
./deploy.sh --only-harbor --harbor-domain registry.example.com
```

#### 僅部署 NFS 服務

```bash
./deploy.sh --only-nfs
```

#### 顯示幫助信息

```bash
./deploy.sh --help
```

#### 顯示詳細使用手冊

```bash
./deploy.sh --manual
```

## 部署流程詳解

### 1. 系統準備 (01-prepare.yml)

- 禁用交換空間(Swap)
- 加載必要的內核模塊
- 設置系統參數
- 配置防火牆規則
- 安裝基礎套件

### 2. 容器運行時安裝 (02-install-runtime.yml)

- 安裝 Docker CE
- 安裝 containerd 和相關依賴
- 安裝 NFS 客戶端工具
- 配置 containerd 使用 systemd cgroup 驅動
- 檢查相關服務狀態

### 3. Kubernetes 安裝 (03-install-k8s.yml)

- 添加 Kubernetes apt 倉庫
- 安裝 kubeadm、kubelet 和 kubectl
- 鎖定版本，防止意外升級

### 4. 主節點初始化 (04-init-master.yml)

- 初始化第一個 master 節點
- 配置 kubectl 工具
- 設置 CoreDNS 容忍度，可以調度到 master 節點
- 設置節點標籤和污點

### 5. 節點加入 (05-join-nodes.yml)

- 生成加入命令
- 其他主節點加入叢集
- 工作節點加入叢集

### 6. 網絡插件部署 (06-setup-cni.yml)

- 部署 Calico 網絡插件
- 配置網絡策略

### 7. NFS 服務器配置 (07-nfs-server.yml)

- 安裝 NFS 服務器
- 配置 NFS 導出目錄
- 啟用 NFSv4 支持
- 開放相關端口

### 8. NFS 客戶端配置 (08-nfs-client.yml)

- 在集群所有節點安裝 NFS 客戶端工具
- 部署 NFS 客戶端 provisioner
- 設置默認 StorageClass

### 9. Harbor 部署 (09-harbor-deploy.yml)

- 安裝 Docker 和 Docker Compose
- 生成 TLS 證書
- 部署 Harbor 容器倉庫
- 配置 Docker 和 Containerd 信任 Harbor 證書
- 設置客戶端節點連接到 Harbor

## 主要特性詳解

### 多主節點高可用

系統支持部署多個主節點，提供高可用控制平面。當您在 `inventory.ini` 中配置多個主節點時，部署腳本會自動設置高可用配置。

### CoreDNS 優化

系統配置了 CoreDNS 的容忍度，使其可以調度到主節點上，這在小型集群中特別有用，可以節省資源。

### NFS 存儲支持

自動部署 NFS 服務器及客戶端，並設置動態存儲供應，讓您可以立即使用 PersistentVolumeClaims。

### 私有容器倉庫

整合了 Harbor 容器倉庫，提供了以下功能：
- 鏡像存儲和分發
- 鏡像掃描（Trivy 集成）
- 基於項目的訪問控制
- 鏡像複製
- 使用 TLS 加密的安全通信

## 故障排除

### 常見問題

1. **節點加入失敗**
   - 檢查網絡連接
   - 確保防火牆允許相關端口
   - 查看 `/var/log/syslog` 或 `journalctl -xeu kubelet`

2. **CoreDNS 未啟動**
   - 驗證網絡插件是否正確部署
   - 檢查 `kubectl get pods -n kube-system` 中 CoreDNS 的狀態
   - 檢查容忍度設置 `kubectl describe pod -n kube-system coredns-xxx`

3. **Harbor 無法訪問**
   - 檢查證書是否正確生成
   - 確認 DNS 解析 (檢查 /etc/hosts)
   - 檢查防火牆規則（443/80 端口）
   - 查看 Harbor 容器狀態 `docker ps`

4. **NFS 存儲問題**
   - 檢查 NFS 服務器是否運行 `systemctl status nfs-kernel-server`
   - 確認客戶端工具已安裝 `ls -la /sbin/mount.nfs`
   - 檢查 NFS provisioner 狀態 `kubectl get pod -l app=nfs-client-provisioner`

### 診斷命令

```bash
# 檢查節點狀態
kubectl get nodes -o wide

# 檢查系統 Pod 狀態
kubectl get pods -n kube-system

# 檢查 Harbor 容器狀態
docker ps | grep harbor

# 檢查 NFS 掛載
showmount -e <nfs-server-ip>

# 檢查 StorageClass
kubectl get storageclass

# 測試存儲
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: nfs-client
EOF

kubectl get pvc
```

## 更新與維護

### 添加新節點

1. 編輯 `inventory.ini` 文件，添加新節點
2. 運行準備和容器運行時安裝:
   ```bash
   ansible-playbook -i inventory.ini playbooks/01-prepare.yml --limit=new-node
   ansible-playbook -i inventory.ini playbooks/02-install-runtime.yml --limit=new-node
   ansible-playbook -i inventory.ini playbooks/03-install-k8s.yml --limit=new-node
   ```
3. 使用加入命令將節點加入集群:
   ```bash
   ansible-playbook -i inventory.ini playbooks/05-join-nodes.yml --limit=new-node
   ```

### 升級 Kubernetes

1. 更新 `group_vars/all.yml` 中的 Kubernetes 版本
2. 運行升級腳本 (待添加)

### 備份與恢復

#### 備份 etcd 數據

在主節點上執行:
```bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db
```

#### 備份 Harbor 數據

```bash
tar -czvf harbor-backup.tar.gz /data/harbor
```

## 安全注意事項

- 在生產環境中，建議更改默認密碼
- Harbor TLS 證書默認為自簽名，生產環境應使用正規 CA 簽名的證書
- 定期更新所有組件以獲取安全修補程序
- 考慮實施網絡策略限制 Pod 間通信

## 貢獻指南

歡迎提交問題報告、功能請求和代碼貢獻。請確保遵循以下準則:
- 遵循現有的代碼風格
- 添加適當的測試和文檔
- 提交前在隔離環境中測試所有更改

## 授權協議

本項目採用 MIT 授權協議 - 詳見 LICENSE 文件 