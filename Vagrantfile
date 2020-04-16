# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

# Define the number of master and worker nodes
# If this number is changed, remember to update $setup_hosts script below with the hosts IP details
NUM_MASTER_NODE = 3
NUM_WORKER_NODE = 2

# Node network
IP_NW = "192.168.5."
MASTER_IP_START = 10
NODE_IP_START = 20
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
    node.vm.provision "setup-hosts", type: "shell", inline: $setup_hosts do |s|
      s.args = ["enp0s8"]
    end
    node.vm.provision "setup-haproxy", type: "shell", path: "scripts/k8s-00-loadbalancer.sh"

  end # loadbalancer

  # Provision Master Nodes
  (1..NUM_MASTER_NODE).each do |i|
    config.vm.define "master-#{i}" do |node|
      # Name shown in the GUI
      node.vm.provider "virtualbox" do |vb|
        vb.name = "kubernetes-ha-master-#{i}"
        vb.memory = 2048
        vb.cpus = 2
      end
      node.vm.hostname = "master-#{i}"
      node.vm.network :private_network, ip: IP_NW + "#{MASTER_IP_START + i}"
      node.vm.network "forwarded_port", guest: 22, host: "#{2710 + i}"

      node.vm.provision "environment-file", type: "file", source: "kubernetes-the-scripted-way.env", destination: "/tmp/kubernetes-the-scripted-way.sh"
      node.vm.provision "setup-environment", type: "shell", inline: "mv /tmp/kubernetes-the-scripted-way.sh /etc/profile.d/"
      
      node.vm.provision "setup-ssh", type: "shell", inline: $setup_ssh, privileged: false
      node.vm.provision "setup-hosts", type: "shell", inline: $setup_hosts do |s|
        s.args = ["enp0s8"]
      end

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
      node.vm.network :private_network, ip: IP_NW + "#{NODE_IP_START + i}"
      node.vm.network "forwarded_port", guest: 22, host: "#{2720 + i}"

      node.vm.provision "environment-file", type: "file", source: "kubernetes-the-scripted-way.env", destination: "/tmp/kubernetes-the-scripted-way.sh"
      node.vm.provision "setup-environment", type: "shell", inline: "mv /tmp/kubernetes-the-scripted-way.sh /etc/profile.d/"
      
      node.vm.provision "setup-ssh", type: "shell", inline: $setup_ssh, privileged: false
      node.vm.provision "setup-hosts", type: "shell", inline: $setup_hosts do |s|
        s.args = ["enp0s8"]
      end
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
IFNAME=$1
ADDRESS="$(ip -4 addr show $IFNAME | grep "inet" | head -1 |awk '{print $2}' | cut -d/ -f1)"
sed -e "s/^.*${HOSTNAME}.*/${ADDRESS} ${HOSTNAME} ${HOSTNAME}.local/" -i /etc/hosts

# remove ubuntu-bionic entry
sed -e '/^.*ubuntu-bionic.*/d' -i /etc/hosts

# Update /etc/hosts about other hosts
cat >> /etc/hosts <<EOF
192.168.5.11  master-1
192.168.5.12  master-2
192.168.5.13  master-3
192.168.5.21  worker-1
192.168.5.22  worker-2
192.168.5.30  lb
EOF
SCRIPT


$install_docker = <<SCRIPT
set -x
curl -fsSL https://get.docker.com | bash
SCRIPT


$allow_bridge_nf_traffic = <<SCRIPT
set -x
modprobe br_netfilter
sysctl net.bridge.bridge-nf-call-iptables=1
sysctl net.bridge.bridge-nf-call-ip6tables=1
sysctl net.bridge.bridge-nf-call-arptables=1

SYSCTL_CONF_LINE="net.bridge.bridge-nf-call-iptables = 1"
grep -qxF "${SYSCTL_CONF_LINE}" /etc/sysctl.conf || (echo ${SYSCTL_CONF_LINE} | tee -a /etc/sysctl.conf)
SYSCTL_CONF_LINE="net.bridge.bridge-nf-call-ip6tables = 1"
grep -qxF "${SYSCTL_CONF_LINE}" /etc/sysctl.conf || (echo ${SYSCTL_CONF_LINE} | tee -a /etc/sysctl.conf)
SYSCTL_CONF_LINE="net.bridge.bridge-nf-call-arptables = 1"
grep -qxF "${SYSCTL_CONF_LINE}" /etc/sysctl.conf || (echo ${SYSCTL_CONF_LINE} | tee -a /etc/sysctl.conf)
SCRIPT
