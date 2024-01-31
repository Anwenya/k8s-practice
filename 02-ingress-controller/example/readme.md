# 通过一个例子验证nic是否配置成功

请求的流程应该如下：

我们的请求 -> inc-service -> inc-pod -> ingress规则 -> nginx-service -> nginx-pod

好像ingress在通过nginx-service能获得到nginx-pod的地址，之后就直接访问nginx-pod，省略了nginx-service转发。

假设已经按照配置文档完成了配置

1. 已经定义了一个IngressClass，名字设置为nic，并指定使用nic（nginx.org/ingress-controller）来控制；这样后续ingress指定使用该IngressClass即可让nic来控制。
2. 已经使用了deploy来启动nic。
3. 已经使用了service来对外提供服务。

## 1.通过deploy部署nginx
```shell
# 创建
kubectl apply -f nginx-deploy.yaml

# 查看状态
kubectl get pod

NAME                            READY   STATUS    RESTARTS   AGE
nginx-deploy-7d74fc48ff-fvc69   1/1     Running   0          13s
nginx-deploy-7d74fc48ff-k7qzh   1/1     Running   0          13s

# 查看详细信息 已经分配了pod ip
kubectl describe pod nginx-deploy-7d74fc48ff-fvc69

Status:           Running
IP:               192.168.178.87
IPs:
  IP:           192.168.178.87

# 直接请求pod的ip是能正常响应的
curl 192.168.178.87

srv : 192.168.178.87:80
host: nginx-deploy-7d74fc48ff-fvc69
uri : GET 192.168.178.87 /
date: 2024-01-31T09:13:40+00:00

```

## 2.创建nginx的service
```shell
# 创建service
kubectl create -f nginx-service.yaml

service/nginx-service created

# 查看状态
kubectl get service

NAME            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)           AGE
envoy           NodePort    10.101.199.218   <none>        10000:32312/TCP   14d
kubernetes      ClusterIP   10.96.0.1        <none>        443/TCP           17d
nginx-service   ClusterIP   10.97.88.115     <none>        80/TCP            11s

# 查看详细信息 能看到已经获得到了pod的ip
kubectl describe svc nginx-service

Name:              nginx-service
Namespace:         default
Labels:            <none>
Annotations:       <none>
Selector:          app=nginx-deploy
Type:              ClusterIP
IP Family Policy:  SingleStack
IP Families:       IPv4
IP:                10.97.88.115
IPs:               10.97.88.115
Port:              <unset>  80/TCP
TargetPort:        80/TCP
Endpoints:         192.168.178.86:80,192.168.178.87:80
Session Affinity:  None
Events:            <none>


# 直接请求service的ip应该也是正常的
# 也能观察到负载均衡的效果
curl 10.97.88.115

srv : 192.168.178.87:80
host: nginx-deploy-7d74fc48ff-fvc69
uri : GET 10.97.88.115 /
date: 2024-01-31T09:17:44+00:00


curl 10.97.88.115

srv : 192.168.178.86:80
host: nginx-deploy-7d74fc48ff-k7qzh
uri : GET 10.97.88.115 /
date: 2024-01-31T09:17:51+00:00
```

## 3.创建ingress
在ingress指定ingressClassName: nic，这样就会被nic控制器来操作了（因为在配置nic的时候创建了一个ingressClass，它的名字是nic，并且在nic-deploy中也指定了nic作为类名）。

```shell

# 创建ingress 其中指定了以 nic.test/ 开头的地址都会转发到 nginx-service的80端口
kubectl apply -f ingress.yml 

ingress.networking.k8s.io/ingress created

# 查看状态
kubectl get ingress

NAME      CLASS   HOSTS      ADDRESS   PORTS   AGE
ingress   nic     nic.test             80      7s

# 查看详情 可以看到rules中的规则正如配置的一样
kubectl describe ingress ingress

Name:             ingress
Labels:           <none>
Namespace:        default
Address:          
Ingress Class:    nic
Default backend:  <default>
Rules:
  Host        Path  Backends
  ----        ----  --------
  nic.test    
              /   nginx-service:80 (192.168.178.86:80,192.168.178.87:80)
Annotations:  <none>
Events:
  Type    Reason          Age   From                      Message
  ----    ------          ----  ----                      -------
  Normal  AddedOrUpdated  35s   nginx-ingress-controller  Configuration for default/ingress was added or updated

```

## 4.访问测试

```shell

# 查看之前配置的service 通过该service来访问nic
kubectl get svc -n nginx-ingress

NAME          TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
nic-service   NodePort   10.110.3.180   <none>        80:31560/TCP,443:32620/TCP   60m

# 要使用域名的方式来访问 不能直接用ip 要符合ingress的匹配规则 否则会404 
# 内部访问
curl --resolve nic.test:80:127.0.0.1 http://nic.test:80

srv : 192.168.178.87:80
host: nginx-deploy-7d74fc48ff-fvc69
uri : GET nic.test /
date: 2024-01-31T09:46:51+00:00

# 外部访问 通过访问的NodePort提供的端口
curl --resolve nic.test:31560:192.168.2.128 http://nic.test:31560

srv : 192.168.178.87:80
host: nginx-deploy-7d74fc48ff-fvc69
uri : GET nic.test /
date: 2024-01-31T09:45:42+00:00

```















