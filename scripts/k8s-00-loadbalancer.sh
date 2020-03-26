#!/usr/bin/env bash
set -euxo pipefail

## Run on Loadbalancer

KUBERNETES_PUBLIC_ADDRESS=192.168.5.30
MASTER_NODES="master-1 master-2 master-3"
KUBERNETS_MASTER_NODE_IPS=192.168.5.11,192.168.5.12,192.168.5.13
MASTER1="master-1 192.168.5.11:6443 check fall 3 rise 2"
MASTER2="master-2 192.168.5.12:6443 check fall 3 rise 2"
MASTER3="master-3 192.168.5.13:6443 check fall 3 rise 2"

#Install HAProxy
sudo apt-get -qq update && sudo apt-get -qq install -y haproxy

cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg 
frontend kubernetes
    bind ${KUBERNETES_PUBLIC_ADDRESS}:6443
    option tcplog
    mode tcp
    default_backend kubernetes-control-plane

backend kubernetes-control-plane
    mode tcp
    balance roundrobin
    option tcp-check
    server ${MASTER1}
    server ${MASTER2}
    server ${MASTER3}
EOF

sudo systemctl restart haproxy
systemctl status --no-pager haproxy

# Verify
nc -zv ${KUBERNETES_PUBLIC_ADDRESS} 6443
