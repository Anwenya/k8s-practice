n=default
f=default
dry-run=--dry-run=client -o yaml

secret:
	kubectl create secret generic $(n)-secret --from-literal=name=root $(dry-run) >> $(n)-secret.yml

cm:
	kubectl create cm $(n)-configmap --from-literal=name=root $(dry-run) >> $(n)-configmap.yml

pod:
	kubectl run $(n)-pod --image=nginx:alpine $(dry-run) >> $(n)-pod.yml

job:
	kubectl create job $(n)-job --image=busybox $(dry-run) >> $(n)-job.yml

cornjob:
	kubectl create cj $(n)-cornjob --image=busybox --schedule="" $(dry-run) >> $(n)-cornjob.yml

.PHONY: all