# 部署wordpress+mariadb

虚拟机环境下想在外部访问，临时转发的话要指定对应的地址

```sh
# 临时创建k8s和本机端口映射 
kubectl port-forward --address 0.0.0.0 wordpress-pod 8080:80 &

# 通过pg调回前台
pg
```