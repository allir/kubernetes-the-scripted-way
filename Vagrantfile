# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

# Define the number of master and worker nodes
NUM_MASTER_NODE = 3
NUM_WORKER_NODE = 2

# Node network
IP_NW = "192.168.5."
MASTER_IP_START = 10
WORKER_IP_START = 20
LB_IP_START = 30

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"

  # Provision Load Balancer Node
  config.vm.define "loadbalancer" do |node|
    node.vm.provider "virtualbox" do |vb|
      vb.name = "kubernetes-ha-lb"
      vb.memory = 512
      vb.cpus = 1
    end
    node.vm.hostname = "loadbalancer"
    node.vm.network :private_network, ip: IP_NW + "#{LB_IP_START}"
	  node.vm.network "forwarded_port", guest: 22, host: 2730

    node.vm.provision "environment-file", type: "file", source: "kubernetes-the-scripted-way.env", destination: "/tmp/kubernetes-the-scripted-way.sh"
    node.vm.provision "setup-environment", type: "shell", inline: "mv /tmp/kubernetes-the-scripted-way.sh /etc/profile.d/"

    node.vm.provision "setup-ssh", type: "shell", inline: $setup_ssh, privileged: false
    node.vm.provision "setup-hosts", type: "shell", inline: $setup_hosts

    node.vm.provision "setup-haproxy", type: "shell", inline: $setup_loadbalancer

  end # loadbalancer

  # Provision Master Nodes
  (1..NUM_MASTER_NODE).each do |i|
    config.vm.define "master-#{i}" do |node|
      # Name shown in the GUI
      node.vm.provider "virtualbox" do |vb|
        vb.name = "kubernetes-ha-master-#{i}"
        vb.memory = 1024
        vb.cpus = 2
      end
      node.vm.hostname = "master-#{i}"
      node.vm.network :private_network, ip: IP_NW + "#{MASTER_IP_START + i}"
      node.vm.network "forwarded_port", guest: 22, host: "#{2710 + i}"

      node.vm.provision "environment-file", type: "file", source: "kubernetes-the-scripted-way.env", destination: "/tmp/kubernetes-the-scripted-way.sh"
      node.vm.provision "setup-environment", type: "shell", inline: "mv /tmp/kubernetes-the-scripted-way.sh /etc/profile.d/"
      
      node.vm.provision "setup-ssh", type: "shell", inline: $setup_ssh, privileged: false
      node.vm.provision "setup-hosts", type: "shell", inline: $setup_hosts

      node.vm.provision "allow-bridge-nf-traffic", type: "shell", inline: $allow_bridge_nf_traffic
      node.vm.provision "install-docker", type: "shell", inline: $install_docker

    end
  end # masters

  # Provision Worker Nodes
  (1..NUM_WORKER_NODE).each do |i|
    config.vm.define "worker-#{i}" do |node|
      node.vm.provider "virtualbox" do |vb|
        vb.name = "kubernetes-ha-worker-#{i}"
        vb.memory = 1024
        vb.cpus = 1
      end
      node.vm.hostname = "worker-#{i}"
      node.vm.network :private_network, ip: IP_NW + "#{WORKER_IP_START + i}"
      node.vm.network "forwarded_port", guest: 22, host: "#{2720 + i}"

      node.vm.provision "environment-file", type: "file", source: "kubernetes-the-scripted-way.env", destination: "/tmp/kubernetes-the-scripted-way.sh"
      node.vm.provision "setup-environment", type: "shell", inline: "mv /tmp/kubernetes-the-scripted-way.sh /etc/profile.d/"
      
      node.vm.provision "setup-ssh", type: "shell", inline: $setup_ssh, privileged: false
      node.vm.provision "setup-hosts", type: "shell", inline: $setup_hosts

      node.vm.provision "allow-bridge-nf-traffic", type: "shell", inline: $allow_bridge_nf_traffic
      node.vm.provision "install-docker", type: "shell", inline: $install_docker

    end
  end # workers

end

$setup_ssh = <<SCRIPT
set -x
cp /vagrant/files/id_rsa* ~/.ssh/
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
SCRIPT


$setup_hosts = <<SCRIPT
set -x
# remove 127.0.1.1 and ubuntu-bionic entry
sed -e '/^127.0.1.1.*/d' -i /etc/hosts
sed -e '/^.*ubuntu-bionic.*/d' -i /etc/hosts

# Update /etc/hosts about other hosts
echo "#{IP_NW}#{LB_IP_START} kubernetes lb loadbalancer" >> /etc/hosts

for i in {1..#{NUM_MASTER_NODE}}; do
  NR=$(expr #{MASTER_IP_START} + ${i})
  echo "#{IP_NW}${NR} master-${i}" >> /etc/hosts
done

for i in {1..#{NUM_WORKER_NODE}}; do
  NR=$(expr #{WORKER_IP_START} + ${i})
  echo "#{IP_NW}${NR} worker-${i}" >> /etc/hosts
done
SCRIPT


$install_docker = <<SCRIPT
set -x
# Install docker
curl -fsSL https://get.docker.com | bash

# Give vagrant user access to docker socket
usermod -aG docker vagrant

# Setup daemon
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

# Restart docker
systemctl daemon-reload
systemctl restart docker
SCRIPT


$allow_bridge_nf_traffic = <<SCRIPT
set -euxo pipefail
lsmod | grep br_netfilter || modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system
SCRIPT


$setup_loadbalancer = <<SCRIPT
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
SCRIPT