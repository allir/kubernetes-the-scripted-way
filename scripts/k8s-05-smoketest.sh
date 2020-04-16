#!/usr/bin/env bash
set -euo pipefail

echo "Running smoketests"

echo "Deploying NGINX"
kubectl create deployment nginx --image=nginx >/dev/null
kubectl scale deployment nginx --replicas=3 >/dev/null
kubectl expose deployment nginx --port=80 --target-port=80 --type NodePort >/dev/null
kubectl get service nginx -o yaml | sed -E "s/nodePort\:.*/nodePort: 30080/" | kubectl apply -f - >/dev/null
kubectl get pod,deployment,service

echo -e "\nWait for the deployment to be ready...\n"
sleep 20

echo "Test the deployment with curl"
for instance in $WORKER_NODES; do
  curl http://${instance}:30080
done

echo -e "\nRun a few more requests to generate logs"
for (( i=0; i<10; ++i)); do
  for instance in $WORKER_NODES; do
    curl http://${instance}:30080 &>/dev/null
  done
done

echo "Get logs"
kubectl logs deployment/nginx

echo -e "\nCleanup"
kubectl delete service nginx >/dev/null
kubectl delete deployment nginx >/dev/null

echo "Done"
