#!/usr/bin/env bash
set -euxo pipefail

# Run on all CONTROL-PLANE nodes

ETCD_CLUSTER=$(for node in $(grep "control-plane" /etc/hosts | awk '{ print $2 "=https://" $1 ":2380" }'); do printf ${node},; done)
ETCD_CLUSTER=${ETCD_CLUSTER%?}
ETCD_SERVERS=$(for node in $(grep "control-plane" /etc/hosts | awk '{ print "https://" $1 ":2379" }'); do printf ${node},; done)
ETCD_SERVERS=${ETCD_SERVERS%?}

{ # Bootstrap ETCD on Control-Plane Nodes
curl -LO https://storage.googleapis.com/etcd/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz

tar -xvf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
sudo mv etcd-${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/

sudo mkdir -p /etc/etcd /var/lib/etcd
sudo cp etcd-ca.pem etcd-server-${HOSTNAME}.pem etcd-server-${HOSTNAME}-key.pem \
  etcd-peer-${HOSTNAME}.pem etcd-peer-${HOSTNAME}-key.pem \
  etcd-healthcheck-client.pem etcd-healthcheck-client-key.pem /etc/etcd/

ETCD_NAME=$(hostname -s)
INTERNAL_IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d / -f 1)

cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --cert-file=/etc/etcd/etcd-server-${HOSTNAME}.pem \\
  --key-file=/etc/etcd/etcd-server-${HOSTNAME}-key.pem \\
  --peer-client-cert-auth=true \\
  --peer-trusted-ca-file=/etc/etcd/etcd-ca.pem \\
  --peer-cert-file=/etc/etcd/etcd-peer-${HOSTNAME}.pem \\
  --peer-key-file=/etc/etcd/etcd-peer-${HOSTNAME}-key.pem \\
  --client-cert-auth=true \\
  --trusted-ca-file=/etc/etcd/etcd-ca.pem \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${ETCD_CLUSTER} \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd

sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/etcd-ca.pem \
  --cert=/etc/etcd/etcd-healthcheck-client.pem \
  --key=/etc/etcd/etcd-healthcheck-client-key.pem
}

{ # Bootstrap Control Plane Components
sudo mkdir -p /etc/kubernetes/config

curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kube-apiserver
curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kube-controller-manager
curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kube-scheduler
chmod +x kubectl kube-apiserver kube-controller-manager kube-scheduler
sudo mv kubectl kube-apiserver kube-controller-manager kube-scheduler /usr/local/bin/

# Kubernetes API
sudo mkdir -p /var/lib/kubernetes/
sudo cp ca.pem ca-key.pem kubernetes.pem kubernetes-key.pem \
  apiserver-kubelet-client.pem apiserver-kubelet-client-key.pem \
  apiserver-etcd-client.pem apiserver-etcd-client-key.pem \
  service-account-key.pem service-account.pem \
  etcd-ca.pem \
  front-proxy-ca.pem front-proxy-ca-key.pem \
  front-proxy-client.pem front-proxy-client-key.pem \
  encryption-config.yaml /var/lib/kubernetes/

INTERNAL_IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d / -f 1)

cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NodeRestriction \\
  --enable-bootstrap-token-auth=true \\
  --etcd-cafile=/var/lib/kubernetes/etcd-ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/apiserver-etcd-client.pem \\
  --etcd-keyfile=/var/lib/kubernetes/apiserver-etcd-client-key.pem \\
  --etcd-servers=${ETCD_SERVERS} \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/apiserver-kubelet-client.pem \\
  --kubelet-client-key=/var/lib/kubernetes/apiserver-kubelet-client-key.pem \\
  --kubelet-https=true \\
  --proxy-client-cert-file=/var/lib/kubernetes/front-proxy-client.pem \\
  --proxy-client-key-file=/var/lib/kubernetes/front-proxy-client-key.pem \\
  --requestheader-client-ca-file=/var/lib/kubernetes/front-proxy-ca.pem \\
  --requestheader-allowed-names=front-proxy-client \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --service-account-issuer=/var/lib/kubernetes/ca.pem \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=${CLUSTER_SERVICE_CIDR} \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Kube Controller Manager
sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --requestheader-client-ca-file=/var/lib/kubernetes/front-proxy-ca.pem \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=${CLUSTER_SERVICE_CIDR} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Kube Scheduler
sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --kubeconfig=/var/lib/kubernetes/kube-scheduler.kubeconfig \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start the Services
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
systemctl status --no-pager kube-apiserver kube-controller-manager kube-scheduler
}

# Verify
echo "Wait for API Server to be ready"
sleep 7
# kubectl get componentstatuses --kubeconfig admin.kubeconfig --- DEPRECATED
# Get the kubernetes API health status, includes etcd health.
curl -k https://localhost:6443/healthz?verbose
# Get the kube-scheduler health status
curl localhost:10251/healthz?verbose
# Get the kube-controller-manager health status
curl localhost:10252/healthz?verbose

kubectl get nodes --kubeconfig admin.kubeconfig
curl --cacert ca.pem https://${LOADBALANCER_IP}:6443/version
