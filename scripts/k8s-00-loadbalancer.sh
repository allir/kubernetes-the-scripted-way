#!/usr/bin/env bash
set -euxo pipefail

LB_IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d / -f 1)
MASTER_NODES=$(grep master /etc/hosts | awk '{print $2}')

## Run on Loadbalancer

#Install HAProxy
sudo apt-get -qq update && sudo apt-get -qq install -y haproxy

cat <<EOF | sudo tee -a /etc/haproxy/haproxy.cfg 

listen stats
    bind :9999
    mode http
    stats enable
    stats hide-version
    stats uri /stats

frontend kubernetes
    bind ${LB_IP}:6443
    mode tcp
    option tcplog
    stats uri /k8sstats
    default_backend kubernetes-control-plane

backend kubernetes-control-plane
    mode tcp
    option tcp-check
    balance roundrobin
EOF

for instance in ${MASTER_NODES}; do
  cat <<EOF | sudo tee -a /etc/haproxy/haproxy.cfg
    server ${instance} $(grep ${instance} /etc/hosts | awk '{print $1}'):6443 check fall 3 rise 2
EOF
done

sudo systemctl restart haproxy
systemctl status --no-pager haproxy

# Verify
nc -zv ${LB_IP} 6443
