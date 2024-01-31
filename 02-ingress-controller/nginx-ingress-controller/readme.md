
# 安装nginx-ingress-controller

官方文档：https://docs.nginx.com/nginx-ingress-controller/installation/installing-nic/installation-with-manifests/

仓库地址：https://github.com/nginxinc/kubernetes-ingress

这里都是先将需要的配置文件从仓库中下载到本地再安装，配置文件在仓库的具体路径参考官方文档。

## 1.先拉取镜像
nginx-ingress-controller是以pod的形式提供服务的。
```bash

crictl pull nginx/nginx-ingress 

```

## 2.创建RBAC

创建 namespace 和 service account

```bash

kubectl apply -f manifests/common/ns-and-sa.yaml

```


创建 role 并绑定到 service account

```bash

kubectl apply -f manifests/rbac/rbac.yaml

```

还有安全选项，这里暂时不配置

## 3.创建通用资源

```bash

kubectl apply -f manifests/common/default-server-secret.yaml

kubectl apply -f manifests/common/nginx-config.yaml

# 这个ic使用nginx-ic来控制
# 后续ingress指定class是这个的name即可
# 如果需要配置为默认的ingress-controller
# 取消 ingressclass.kubernetes.io/is-default-class 的注释
# 这样未指定ClassName的ingress都会默认使用这个Class指定的nic
kubectl apply -f manifests/common/ingress-class.yaml

```

## 4.创建自定义资源

```bash

kubectl apply -f manifests/common/crds/k8s.nginxorg_virtualservers.yaml
kubectl apply -f manifests/common/crds/k8s.nginx.org_virtualserverroutes.yaml
kubectl apply -f manifests/common/crds/k8s.nginx.org_transportservers.yaml
kubectl apply -f manifests/common/crds/k8s.nginx.org_policies.yaml
kubectl apply -f manifests/common/crds/k8s.nginx.org_globalconfigurations.yaml

```


## 5.启动nginx-ingress-controller
前面都是创建各种配置，这里是启动nic的pod。
有多种部署方式，这里以官网的例子用deployment的形式部署
```bash
# 可以指定该参数 -ingress-class=nic 
kubectl apply -f manifests/nic-deploy.yaml

```
确认启动成功

```bash
kubectl get pods --namespace=nginx-ingress
NAME                            READY   STATUS    RESTARTS   AGE
nginx-ingress-f95c6d79f-gjzwb   1/1     Running   0          59m


kubectl get deploy --namespace=nginx-ingress
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
nginx-ingress   1/1     1            1           62m
```

## 6.外部访问

通过service并设置为NodePort对外暴露一个端口
```bash

kubectl create -f manifests/nic-service.yaml

```