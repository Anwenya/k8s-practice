**ps：ubuntu 22.04 + kubeadm +  containerd + calico 安装1.28.2 的 单节点 集群**

# 1. 安装虚拟机

略

# 2. 安装 Ubuntu 22.04.3 LTS

安装略

镜像源在开机时就可以配置

```
mirrors.aliyun.com/ubuntu/
```

root密码

```
sudo passwd root
```

root远程登陆

```shell
vim /etc/ssh/sshd_config
PermitRootLogin yes
# 重启ssh服务
```

这里都是正常安装，也没有配置静态ip

```shell
# /etc/netplan/00-installer-config.yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens33:
      dhcp4: true
  version: 2
```

```shell
ens33: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.133.133  netmask 255.255.255.0  broadcast 192.168.133.255
        inet6 fe80::20c:29ff:feae:dec9  prefixlen 64  scopeid 0x20<link>
        ether 00:0c:29:ae:de:c9  txqueuelen 1000  (Ethernet)
        RX packets 678124  bytes 896473234 (896.4 MB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 191834  bytes 106424265 (106.4 MB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

使用 192.168.133.133 作为master的ip

# 3. 前置配置

## 1. 关闭交换内存

kubernetes要求关闭交换内存 以此来提升性能

```shell
# 临时关闭
root@master:~/kube# swapoff -a
# 永久关闭 修改配置文件 注释掉文件内以swap开头的行
vim /etc/fstab
# /swap.img     none    swap    sw      0       0
```

验证是否关闭

```shell
# 查看内存状态 如果swap都是0则证明没有开启交换内存
root@master:~/kube# free -mh
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       1.2Gi       136Mi       4.0Mi       2.4Gi       2.3Gi
Swap:             0B          0B          0B
```

## 2. 配置静态ip

可以选择单独配置一个静态ip作为kubernetes的ip，目前虚拟机的ip也不会变化，故省略此步。

## 3. 配置host映射

为避免通过节点名找不到主机，在这里配置上映射

```
192.168.133.133 master 
```

## 4. 更改时区

配置时区为上海

```shell
timedatectl set-timezone Asia/Shanghai

root@master:~/kube# timedatectl
               Local time: Sat 2024-01-27 16:56:26 CST
           Universal time: Sat 2024-01-27 08:56:26 UTC
                 RTC time: Sat 2024-01-27 08:56:26
                Time zone: Asia/Shanghai (CST, +0800)
System clock synchronized: yes
              NTP service: active
          RTC in local TZ: no
```

多节点应该要定时同步各节点机器的时间，这里单节点配置暂略。

## 5. 配置转发

该配置用于集群内部快速通信

```shell
# 手动加载模块
modprobe overlay
modprobe br_netfilter

# 验证已加载模块
lsmod | egrep "overlay"
lsmod | egrep "br_netfilter"

root@master:~/kube# lsmod | egrep "overlay"
overlay               151552  33
root@master:~/kube# lsmod | egrep "br_netfilter"
br_netfilter           32768  0
bridge                307200  1 br_netfilter
```

添加网桥过滤及内核转发配置

```shell
cat << EOF|tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward=1 # better than modify /etc/sysctl.conf
EOF

# 加载上述配置 以下两种方式选一个即可
# 指定文件加载
sysctl -p /etc/sysctl.d/k8s.conf
# 加载所有
sysctl --system

root@master:~/kube# sysctl -p /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1 # better than modify /etc/sysctl.conf
```

## 6. 更改cgroup驱动

应该将cgroup驱动更改为systemd，具体会在下面安装containerd时配置。

如果是使用docker的containerd，需要在docker的配置文件中也进行更改（保险操作）。

```shell
# /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn/"
  ],
  "dns": [
    "8.8.8.8",
    "114.114.114.114"
  ],
  "insecure-registries": [],
  "exec-opts": ["native.cgroupdriver=systemd"]
}
```

# 4. 配置containerd

这是单独安装containerd的方式，新版本的kubernetes默认会使用containerd。

## 1. 下载

到github上下载对应的包即可。这里是1.7.11版本。

```shell
wget -e "https_proxy=192.168.0.101:7890" https://github.com/containerd/containerd/releases/download/v1.7.11/cri-containerd-1.7.11-linux-amd64.tar.gz
```

解压到根目录即可，会自动合并具体的目录。

```shell
tar xf cri-containerd-1.7.11-linux-amd64.tar.gz -C /
```

## 2. 配置

创建配置文件，默认是没有的。

```
mkdir /etc/containerd
```

输出一份默认配置

```shell
containerd config default > /etc/containerd/config.toml
```

修改其中的两个配置

```shell
# 使用阿里云的仓库并把版本调整到3.9 默认是3.8
# 因为我们安装的1.28.2的版本默认需要3.9版本的pause
registry.aliyuncs.com/google_containers/pause:3.9
# 使用systemd作为cgroup的驱动
SystemdCgroup:true
```

## 3. 启动

查看runc的版本

```shell
# ubuntu中的runc是正常的 在centos下的话要有额外的配置
runc --version

root@master:~/kube# runc --version
runc version 1.1.10
commit: v1.1.10-0-g18a0cb0f
spec: 1.0.2-dev
go: go1.20.12
libseccomp: 2.5.3
```

配置立即启动和开机自启动

```shell
systemctl enable --now containerd
```

查看版本

```shell
containerd --version
containerd github.com/containerd/containerd v1.7.11 64b8a811b07ba6288238eefc14d898ee0b5b99ba
```

尝试拉取下镜像

```shell
crictl pull registry.aliyuncs.com/google_containers/pause:3.9

crictl images
```

```shell
# 如果是使用docker的话不一定有crictl工具，后续安装kubeadm的时候会再安装，而且要额外配置runtime-endpoint

# 切换runtime-endpoint (非正常流程 遇到相关问题再操作)
crictl config runtime-endpoint unix:///run/containerd/containerd.sock

# 重启containerd (非正常流程 遇到相关问题再操作)
systemctl daemon-reload && systemctl restart containerd

# 按照本文档的操作流程是先配置后启动的，因此不用关心这一块，遇到相关问题再看。
```

# 5. 安装kubeadm、kubectl、kubelet

配置软件源

```shell
# 安装可能用到的工具
apt install -y apt-transport-https ca-certificates curl

# 使用阿里云的仓库
# 配置阿里云密钥
curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -

# 配置软件源
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF

# 更新
apt update
```

可以确认一下有没有这些包

```shell
# 查看列表
apt-cache policy kubeadm
# 查看软件列表及依赖关系
apt-cache showpkg kubeadm
```

安装指定的版本

```shell
# 安装指定的版本
apt install -y kubeadm=1.28.2-00 kubelet=1.28.2-00 kubectl=1.28.2-00

# 查看安装的版本
kubeadm version
kubectl version --client

# 锁定版本, 避免无意间更新
apt-mark hold kubeadm kubelet kubectl

# 有需要再解锁
apt-mark hold kubeadm kubelet kubectl
```

避免kubelet启动异常，提前指定启动配置文件

```shell
vim /lib/systemd/system/kubelet.service

ExecStart=/usr/bin/kubelet --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml

# 这些配置文件是kubeadm init时创建的
# 之后kubeadm会重启kubelet服务，就可以用新配置启动了
```

确认各组件的版本

```shell
# 查看该版本的k8s对应的各组件的版本
kubeadm config images list --kubernetes-version v1.28.2

root@master:~/kube# kubeadm config images list --kubernetes-version v1.28.2
registry.k8s.io/kube-apiserver:v1.28.2
registry.k8s.io/kube-controller-manager:v1.28.2
registry.k8s.io/kube-scheduler:v1.28.2
registry.k8s.io/kube-proxy:v1.28.2
registry.k8s.io/pause:3.9
registry.k8s.io/etcd:3.5.9-0
registry.k8s.io/coredns/coredns:v1.10.1

# 这也是上面为什么修改pause版本的原因
# 我们使用阿里云的仓库，实际安装后各镜像的标签应该是
root@master:~/kube# crictl images
IMAGE                                                             TAG                 IMAGE ID            SIZE
registry.aliyuncs.com/google_containers/coredns                   v1.10.1             ead0a4a53df89       16.2MB
registry.aliyuncs.com/google_containers/etcd                      3.5.9-0             73deb9a3f7025       103MB
registry.aliyuncs.com/google_containers/kube-apiserver            v1.28.2             cdcab12b2dd16       34.7MB
registry.aliyuncs.com/google_containers/kube-controller-manager   v1.28.2             55f13c92defb1       33.4MB
registry.aliyuncs.com/google_containers/kube-proxy                v1.28.2             c120fed2beb84       24.6MB
registry.aliyuncs.com/google_containers/kube-scheduler            v1.28.2             7a5d9d67a13f6       18.8MB
registry.aliyuncs.com/google_containers/pause                     3.9                 e6f1816883972       322kB
```

配置kubeadm

```shell
# 创建kubeadm的初始化配置文件并修改
kubeadm config print init-defaults > kubeadm-config.yaml

# 需要修改一些地方来契合我们的配置
# 主机地址 修改为我们本机的ip
advertiseAddress:192.168.133.133

# 高版本默认就是unix:///var/run/containerd/containerd.sock
# 该值表示使用containerd
criSocket:

# 节点名
name:master

# 镜像仓库 使用阿里云的仓库 否则可能受到限制
# 这也是上面提到的镜像标签会变的原因
imageRepository: registry.aliyuncs.com/google_containers

# pod网络 
# 在最后增加一行配置表示pod的网段 不要与主机的网段有冲突
networking:
    # 增加pod的网段配置
    podSubnet: 10.244.0.0/16
    
# 指定kubelet使用systemd
# 在配置文件最后增加一段配置
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
```

初始化集群

```shell
# 通过配置文件初始化
kubeadm init --config kubeadm-config.yaml

# 通过命令参数的方式初始化,不推荐
kubeadm init \
 --image-repository registry.aliyuncs.com/google_containers \
 --kubernetes-version v1.28.2 \
 --pod-network-cidr=10.10.0.0/16 \
 --cri-socket /run/containerd/containerd.sock \
 --apiserver-advertise-address=192.168.10.2

# 这时集群应该能正常部署
# 之后拷贝配置文件即可 用于鉴权
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# 查看节点状态
kubectl get node
 
# 目前coresdns pod应该是pending状态 因为还没有安装网络插件
root@master:~/kube# kubectl get pod -n kube-system
NAME                             READY   STATUS    RESTARTS   AGE
coredns-66f779496c-46hsl         0/1     Pending   0          10m
coredns-66f779496c-rt5rj         0/1     Pending   0          10m
etcd-master                      1/1     Running   0          10m
kube-apiserver-master            1/1     Running   0          10m
kube-controller-manager-master   1/1     Running   0          10m
kube-proxy-m9t5r                 1/1     Running   0          10m
kube-scheduler-master            1/1     Running   0          10m
```

# 6. 安装calico

```shell
# 官方文档
https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart

# 通过网络文件创建
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# 网络不好可以先把配置文件下载下来再配置
wget -e "https_proxy=192.168.0.101:7890"  https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
# 通过下载的配置文件创建
kubectl create -f tigera-operator.yaml

# 上面的操作会添加一个命名空间 tigera-operator
root@master:~/kube# kubectl get ns
NAME              STATUS   AGE
default           Active   43m
kube-node-lease   Active   43m
kube-public       Active   43m
kube-system       Active   43m
tigera-operator   Active   6s

# 查看一下pod的状态 一定要等该pod running之后再进行下一步 ！！！
root@master:~/kube# kubectl get pods -n tigera-operator
NAME                               READY   STATUS    RESTARTS   AGE
tigera-operator-55585899bf-9lsb7   1/1     Running   0          16s

# 和第一步类似 但是要改一下文件内容
wget -e "https_proxy=192.168.0.101:7890"  https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

# 将配置文件的cidr更换为我们上面定义的pod的网段
cidr: 10.244.0.0/16

# 确认网段与之前指定的一致后再创建
kubectl create -f custom-resources.yaml


# 正常到这里会有一个calico-system的命名空间
root@master:~/kube# kubectl get ns
NAME              STATUS   AGE
calico-system     Active   4s
default           Active   44m
kube-node-lease   Active   44m
kube-public       Active   44m
kube-system       Active   44m
tigera-operator   Active   45s

# 查看calico-system各pod的状态 等待它们启动成功 可能要3分钟左右
root@master:~/kube# kubectl get pods -n calico-system
NAME                                       READY   STATUS              RESTARTS   AGE
calico-kube-controllers-8656d4bf56-7wtrh   0/1     Pending             0          27s
calico-node-d9jvd                          0/1     Init:0/2            0          27s
calico-typha-5dd576747b-wtprb              0/1     ContainerCreating   0          27s
csi-node-driver-rcw88                      0/2     ContainerCreating   0          27s

# 等到都running后就完成了 单节点的情况需要先让master参与调度
root@master:~/kube# kubectl get pods -n calico-system
NAME                                       READY   STATUS    RESTARTS   AGE
calico-kube-controllers-8656d4bf56-7wtrh   1/1     Running   0          3m57s
calico-node-d9jvd                          1/1     Running   0          3m57s
calico-typha-5dd576747b-wtprb              1/1     Running   0          3m57s
csi-node-driver-rcw88                      2/2     Running   0          3m57s

# 这时节点的状态应该是ready的
root@master:~/kube# kubectl get node
NAME     STATUS   ROLES           AGE   VERSION
master   Ready    control-plane   48m   v1.28.2
```

# 7. 验证集群

配置一个nginx的deployment来验证是否正常

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginxweb
spec:
  selector:
    matchLabels:
      app: nginxweb1
  replicas: 2
  template:
    metadata:
      labels:
        app: nginxweb1
    spec:
      containers:
      - name: nginxwebc
        image: nginx:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginxweb-service
spec:
  externalTrafficPolicy: Cluster
  selector:
    app: nginxweb1
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30080
  type: NodePort
```

```shell
kubectl apply -f nginx.yaml

root@master:~/kube# kubectl get deployment 
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
nginxweb   2/2     2            2           3h14m

root@master:~/kube# kubectl get pod
NAME                        READY   STATUS    RESTARTS   AGE
nginxweb-64c569cccc-g46x5   1/1     Running   0          3h14m
nginxweb-64c569cccc-lr2xr   1/1     Running   0          3h14m

# 查看log
root@master:~# kubectl logs nginxweb-64c569cccc-g46x5
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
/docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
/docker-entrypoint.sh: Configuration complete; ready for start up
2024/01/27 06:36:07 [notice] 1#1: using the "epoll" event method
2024/01/27 06:36:07 [notice] 1#1: nginx/1.25.3
2024/01/27 06:36:07 [notice] 1#1: built by gcc 12.2.0 (Debian 12.2.0-14) 
2024/01/27 06:36:07 [notice] 1#1: OS: Linux 5.15.0-92-generic
2024/01/27 06:36:07 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 1048576:1048576
2024/01/27 06:36:07 [notice] 1#1: start worker processes
2024/01/27 06:36:07 [notice] 1#1: start worker process 29
2024/01/27 06:36:07 [notice] 1#1: start worker process 30
...

# 查看详情
root@master:~# kubectl describe pod nginxweb-64c569cccc-g46x5
Name:             nginxweb-64c569cccc-g46x5
Namespace:        default
Priority:         0
Service Account:  default
Node:             master/192.168.133.133
...
Status:           Running
IP:               10.244.219.71
IPs:
  IP:           10.244.219.71
...
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:                      <none>

root@master:~# kubectl get service
NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes         ClusterIP   10.96.0.1       <none>        443/TCP        4h14m
nginxweb-service   NodePort    10.108.129.56   <none>        80:30080/TCP   3h16m

# 验证在内部通过 10.108.129.56:80 能否访问nginx
# 验证在外部能否通过 192.168.133.133:30080 能否访问nginx
```

# 8. 污染节点

```shell
# 单节点情况下 删除master的taint 让master参与调度
 kubectl taint nodes --all node.kubernetes.io/not-ready-
 kubectl taint nodes --all node-role.kubernetes.io/control-plane-
 node.kubernetes.io/not-ready:NoSchedule
```

# 9. 异常

如果没有正常启动可以查看相关的日志来定位问题

```shell
root@master:~# systemctl status kubelet
root@master:~# journalctl -xeu kubelet

# 查看容器状态
root@master:~# crictl ps
# 直接查看容器的log
root@master:~/kube# crictl logs 18dce3182e9eb

# 查看资源详情 最下方的event可能有有用信息
root@master:~# kubectl describe pod calico-kube-controllers-7697f97d8b-g4kwb -n calico-system
# 查看log
root@master:~# kubectl logs coredns-66f779496c-4g5bw -n kube-system

# 重启大法等等
```



# 10. 模板

```yaml
# kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.133.133
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  name: master
  taints: null
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.aliyuncs.com/google_containers
kind: ClusterConfiguration
kubernetesVersion: 1.28.2
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
  podSubnet: 10.244.0.0/16
scheduler: {}
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
```



