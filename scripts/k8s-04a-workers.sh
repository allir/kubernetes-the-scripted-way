#!/usr/bin/env bash
set -euxo pipefail

# Run on all WORKER nodes
## Manual Bootstrap

{ # Setup dependencies
  sudo apt -qq update && sudo apt -qq install -y socat conntrack ipset
}

{ # Install Kubernetes Components (WORKER)
curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kubelet
curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kube-proxy
curl -LO https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz

sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

sudo tar -xzvf cni-plugins-linux-amd64-${CNI_VERSION}.tgz --directory /opt/cni/bin/
chmod +x kubectl kube-proxy kubelet
sudo mv kubectl kube-proxy kubelet /usr/local/bin/

# Kubelet
sudo cp ${HOSTNAME}-key.pem ${HOSTNAME}.pem /var/lib/kubelet/
sudo cp ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ca.pem /var/lib/kubernetes/

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "${KUBERNETES_DNS_IP}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${HOSTNAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${HOSTNAME}-key.pem"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --cgroup-driver=systemd \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Kube Proxy
sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "${CLUSTER_CIDR}"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start the Services
sudo systemctl daemon-reload
sudo systemctl enable kubelet kube-proxy
sudo systemctl start kubelet kube-proxy
systemctl status --no-pager kubelet kube-proxy
}

# Label master nodes with role
if [[ ${HOSTNAME} == "master-"* ]]; then
  # Wait for the node to show up
  sleep 7
  kubectl --kubeconfig admin.kubeconfig label node ${HOSTNAME} node-role.kubernetes.io/master=
fi
