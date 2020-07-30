# kubernetes-the-scripted-way

Kubernetes-the-hard-way (KTHW) on Vagrant... Scripted

## Requirements

* VirtualBox
* Vagrant

### Installing Requirements

#### macOS

Using `homebrew`

```bash
brew cask install virtualbox virtualbox virtualbox-extension-pack

brew cask install vagrant
```

## Using

### Provisioning with Vagrant

The default setup sets up a loadbalancer node, three master nodes and two worker nodes.

To stand up a new environment

```bash
vagrant up
```

Connecting to the nodes `vagrant ssh <node>`. Example:

```bash
vagrant ssh master-1
```

### Kubernetes setup

1. Setup PKI, Certificates and Kubeconfigs

    ```bash
    # On master-1 run the setup script
    /vagrant/scripts/k8s-01-setup.sh
    ```

2. Setup the Control Plane (master nodes)

    ```bash
    # On ALL of the master nodes run the master setup script
    /vagrant/scripts/k8s-02-masters.sh
    ```

3. Setup Kube-apiserver RBAC, Node Bootstrapping, Networking and Cluster DNS resources

    ```bash
    # On master-1 run the resources setup script
    /vagrant/scripts/k8s-03-resources.sh
    ```

4. Setup Worker Nodes

    There are two ways to set up the worker nodes. With manually created certificates and configuration or using the TLS Bootstrapping to automatically generate the certificates.

    The required certificates are created during step 1 so either way will work. You can provision all the worker nodes the same way or each one differently.

    NOTE: We can/should also run this on the master nodes so they'll be visible in the cluster and join the cluster networking.

    a. Manually created certificate

    ```bash
    # On one or more master & worker nodes run the worker setup script
    /vagrant/scripts/k8s-04a-workers.sh
    ```

    b. TLS Bootstrap

    ```bash
    # On one or more master & worker nodes run the worker bootstrap setup script
    /vagran/scripts/k8s-04b-workers-tls.sh

    # On master-1 check the worker node Certificate request and approve it
    kubectl get csr
    ## OUTPUT:
    ## NAME         AGE     REQUESTOR               CONDITION
    ## csr-95bv6    20s     system:node:worker-2    Pending

    kubectl certificate approve csr-95bv6
    ```

5. Verification

    Let's check the health of the etcd cluster, control plane and worker nodes and their components

    ```bash
    # On master-1

    # ETCD member list
    sudo ETCDCTL_API=3 etcdctl member list --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/etcd-server.pem --key=/etc/etcd/etcd-server-key.pem
    ## 45bf9ccad8d8900a, started, master-2, https://192.168.5.12:2380, https://192.168.5.12:2379, false
    ## 54a5796a6803f252, started, master-1, https://192.168.5.11:2380, https://192.168.5.11:2379, false
    ## da27c13c21936c01, started, master-3, https://192.168.5.13:2380, https://192.168.5.13:2379, false

    # ETCD endpoint health
    sudo ETCDCTL_API=3 etcdctl endpoint health  --endpoints=https://192.168.5.11:2379,https://192.168.5.12:2379,https://192.168.5.13:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/etcd-server.pem --key=/etc/etcd/etcd-server-key.pem
    ## https://192.168.5.11:2379 is healthy: successfully committed proposal: took = 11.698581ms
    ## https://192.168.5.13:2379 is healthy: successfully committed proposal: took = 12.404629ms
    ## https://192.168.5.12:2379 is healthy: successfully committed proposal: took = 17.80096ms

    # Control Plane components
    kubectl get componentstatuses
    ## NAME                 STATUS    MESSAGE             ERROR
    ## controller-manager   Healthy   ok
    ## scheduler            Healthy   ok
    ## etcd-2               Healthy   {"health":"true"}
    ## etcd-0               Healthy   {"health":"true"}
    ## etcd-1               Healthy   {"health":"true"}

    # Ndoe status
    kubectl get nodes
    ## NAME       STATUS   ROLES    AGE     VERSION
    ## worker-1   Ready    <none>   4m20s   v1.18.0
    ## worker-2   Ready    <none>   4m21s   v1.18.0

    # Check version via loadbalancer
    curl --cacert ca.pem https://192.168.5.30:6443/version
    ## {
    ##   "major": "1",
    ##   "minor": "18",
    ##   "gitVersion": "v1.18.0",
    ##   "gitCommit": "9e991415386e4cf155a24b1da15becaa390438d8",
    ##   "gitTreeState": "clean",
    ##   "buildDate": "2020-03-25T14:50:46Z",
    ##   "goVersion": "go1.13.8",
    ##   "compiler": "gc",
    ##   "platform": "linux/amd64"
    ## }

    # Test cluster DNS
    kubectl run dnsutils --image="gcr.io/kubernetes-e2e-test-images/dnsutils:1.3" --command -- sleep 4800
    ## pod/dnsutils created
    kubectl exec dnsutils -- nslookup kubernetes.default
    ## Server:      10.96.0.10
    ## Address:     10.96.0.10#53

    ## Name:    kubernetes.default.svc.cluster.local
    ## Address: 10.96.0.1

    kubectl delete pod dnsutils
    ## pod "dnsutils" deleted
    ```

### Smoke Tests

Let's set up an NGINX deployment and service as a smoke test. This can be run from `master-1` node or using the `admin.kubeconfig` in the repository folder after provisioning.

```bash
kubectl create deployment nginx --image=nginx
## deployment.apps/nginx created

kubectl scale deployment nginx --replicas=3
## deployment.apps/nginx scaled

kubectl expose deployment nginx --port=80 --target-port=80 --type NodePort
## service/nginx exposed

kubectl get service nginx -o yaml | sed -E "s/nodePort\:.*/nodePort: 30080/" | kubectl apply -f -
## Warning: kubectl apply should be used on resource created by either kubectl create --save-config or kubectl apply
## service/nginx configured

kubectl get pod,deployment,service
## NAME                        READY   STATUS    RESTARTS   AGE
## pod/nginx-f89759699-7lr85   1/1     Running   0          3m37s
## pod/nginx-f89759699-gn97b   1/1     Running   0          3m30s
## pod/nginx-f89759699-l5bjt   1/1     Running   0          3m30s
##
## NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
## deployment.apps/nginx   3/3     3            3           3m37s
##
## NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)        AGE
## service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP        43m
## service/nginx        NodePort    10.96.0.67   <none>        80:30080/TCP   104s

curl http://worker-1:30080 && curl http://worker-2:30080
## <!DOCTYPE html>
## <html>
## <head>
## <title>Welcome to nginx!</title>
## <style>
##     body {
##         width: 35em;
##         margin: 0 auto;
##         font-family: Tahoma, Verdana, Arial, sans-serif;
##     }
## </style>
## </head>
## <body>
## <h1>Welcome to nginx!</h1>
## <p>If you see this page, the nginx web server is successfully installed and
## working. Further configuration is required.</p>
##
## <p>For online documentation and support please refer to
## <a href="http://nginx.org/">nginx.org</a>.<br/>
## Commercial support is available at
## <a href="http://nginx.com/">nginx.com</a>.</p>
##
## <p><em>Thank you for using nginx.</em></p>
## </body>
## </html>
## ...

# Let's generate some logs and then check logging. This verifies kube-apiserver to kubelet RBAC permissions.
for (( i=0; i<50; ++i)); do
    curl http://worker-1:30080 &>/dev/null && curl http://worker-2:30080 &>/dev/null
done
kubectl logs deployment/nginx
## Found 3 pods, using pod/nginx-f89759699-7lr85
## 10.32.0.1 - - [26/Mar/2020:13:48:07 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/7.58.0" "-"
## 10.32.0.1 - - [26/Mar/2020:13:55:38 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/7.58.0" "-"
## 10.44.0.0 - - [26/Mar/2020:13:55:38 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/7.58.0" "-"
## ...
```

### Conclusion

Awesome!

## Cleanup

Destroy the machines and clean up temporary files from the repository.

```bash
vagrant destroy -f
git clean -xf
```
