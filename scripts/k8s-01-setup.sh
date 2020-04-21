#!/usr/bin/env bash
set -euxo pipefail

# Run on master-1 

{ # Install CFSSL
  curl -L https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o cfssl
  curl -L https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o cfssljson

  chmod +x cfssl cfssljson

  sudo mv cfssl cfssljson /usr/local/bin/
}

{ # Install kubectl
  curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/bin/linux/amd64/kubectl

  chmod +x kubectl

  sudo mv kubectl /usr/local/bin/
}

{ # Setup CAs 
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "server": {
        "usages": ["signing", "key encipherment", "server auth"],
        "expiry": "8760h"
      },
      "client": {
        "usages": ["signing", "key encipherment", "client auth"],
        "expiry": "8760h"
      },
      "server-client": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
  "CA": {
    "expiry": "87660h",
    "pathlen": 0
  },
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "Kubernetes",
      "OU": "CA"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

cat > front-proxy-ca-csr.json <<EOF
{
  "CA": {
    "expiry": "87660h",
    "pathlen": 0
  },
  "CN": "front-proxy-ca",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "Kubernetes",
      "OU": "CA"
    }
  ]
}
EOF

cfssl gencert -initca front-proxy-ca-csr.json | cfssljson -bare front-proxy-ca

cat > etcd-ca-csr.json <<EOF
{
  "CA": {
    "expiry": "87660h",
    "pathlen": 0
  },
  "CN": "etcd-ca",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "Kubernetes",
      "OU": "CA"
    }
  ]
}
EOF

cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare etcd-ca
}


{ # Generate Admin Certificate
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  admin-csr.json | cfssljson -bare admin
}

{ # Generate Kubelet Certificates
for instance in $MASTER_NODES $WORKER_NODES; do
cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

INTERNAL_IP=$(grep ${instance} /etc/hosts | head -1 | cut -d' ' -f1)

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=server-client \
  -hostname=${instance},${INTERNAL_IP} \
  ${instance}-csr.json | cfssljson -bare ${instance}
done
}

{ # Generate Controller Manager Certificate
cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
}


{ # Generate Kube-Proxy Certificate
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  kube-proxy-csr.json | cfssljson -bare kube-proxy
}


{ # Generate Kube-Scheduler Certificate
cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler
}


{ # Generate Kubernetes API (kube-apiserver) Server Certificate
KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local
MASTER_NODE_IPS=$(for ip in $(grep master /etc/hosts | awk '{print $1}'); do printf ${ip},; done)
MASTER_NODE_IPS=${MASTER_NODE_IPS%?}

cat > kubernetes-csr.json <<EOF
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${KUBERNETES_SERVICE_IP},${MASTER_NODE_IPS},${LOADBALANCER_IP},127.0.0.1,${KUBERNETES_HOSTNAMES} \
  -profile=server \
  kubernetes-csr.json | cfssljson -bare kubernetes
}


{ # Generate kube-apiserver kublet client certificate
cat > apiserver-kubelet-client-csr.json <<EOF
{
  "CN": "kube-apiserver-kubelet-client",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  apiserver-kubelet-client-csr.json | cfssljson -bare apiserver-kubelet-client
}


{ # Generate kube-apiserver etcd client certificate
cat > apiserver-etcd-client-csr.json <<EOF
{
  "CN": "kube-apiserver-etcd-client",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=etcd-ca.pem \
  -ca-key=etcd-ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  apiserver-etcd-client-csr.json | cfssljson -bare apiserver-etcd-client
}


{ # Generate ETCD Server Certificates
for instance in $MASTER_NODES; do
cat > etcd-server-${instance}-csr.json <<EOF
{
  "CN": "${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

INTERNAL_IP=$(grep ${instance} /etc/hosts | head -1 | cut -d' ' -f1)

cfssl gencert \
  -ca=etcd-ca.pem \
  -ca-key=etcd-ca-key.pem \
  -config=ca-config.json \
  -hostname=${instance},localhost,${INTERNAL_IP},127.0.0.1 \
  -profile=server-client \
  etcd-server-${instance}-csr.json | cfssljson -bare etcd-server-${instance}
done
}


{ # Generate ETCD Peer Certificates
for instance in $MASTER_NODES; do
cat > etcd-peer-${instance}-csr.json <<EOF
{
  "CN": "${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

INTERNAL_IP=$(grep ${instance} /etc/hosts | head -1 | cut -d' ' -f1)

cfssl gencert \
  -ca=etcd-ca.pem \
  -ca-key=etcd-ca-key.pem \
  -config=ca-config.json \
  -hostname=${instance},localhost,${INTERNAL_IP},127.0.0.1 \
  -profile=server-client \
  etcd-peer-${instance}-csr.json | cfssljson -bare etcd-peer-${instance}
done
}

{ # Generate ETCD healthcheck client Certificates
cat > etcd-healthcheck-client-csr.json <<EOF
{
  "CN": "kube-etcd-healthcheck-client",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=etcd-ca.pem \
  -ca-key=etcd-ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  etcd-healthcheck-client-csr.json | cfssljson -bare etcd-healthcheck-client
}


{ # Generate Service Account Certificate
cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  service-account-csr.json | cfssljson -bare service-account
}

{ # Generate Front-Proxy Client Certificate
cat > front-proxy-client-csr.json <<EOF
{
  "CN": "front-proxy-client",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IS",
      "L": "Reykjavik",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes The Hard Way"
    }
  ]
}
EOF

cfssl gencert \
  -ca=front-proxy-ca.pem \
  -ca-key=front-proxy-ca-key.pem \
  -config=ca-config.json \
  -profile=client \
  front-proxy-client-csr.json | cfssljson -bare front-proxy-client
}


{ # Copy Certificates to master & worker nodes
for instance in $WORKER_NODES; do
  scp -o StrictHostKeyChecking=no ca.pem ${instance}-key.pem ${instance}.pem ${instance}:~/
done

for instance in $MASTER_NODES; do
  scp -o StrictHostKeyChecking=no \
    ca.pem ca-key.pem \
    kubernetes-key.pem kubernetes.pem \
    apiserver-kubelet-client-key.pem apiserver-kubelet-client.pem \
    apiserver-etcd-client-key.pem apiserver-etcd-client.pem \
    ${instance}.pem ${instance}-key.pem \
    admin-key.pem admin.pem \
    service-account-key.pem service-account.pem \
    etcd-ca-key.pem etcd-ca.pem \
    etcd-server-${instance}-key.pem etcd-server-${instance}.pem \
    etcd-peer-${instance}-key.pem etcd-peer-${instance}.pem \
    etcd-healthcheck-client-key.pem etcd-healthcheck-client.pem \
    front-proxy-ca.pem front-proxy-ca-key.pem \
    front-proxy-client.pem front-proxy-client-key.pem ${instance}:~/
done
}

{ # Generate kubeconfig files
for instance in $MASTER_NODES $WORKER_NODES; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${LOADBALANCER_IP}:6443 \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=${instance}.pem \
    --client-key=${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance} \
    --kubeconfig=${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=${instance}.kubeconfig
done

{ # Generate Kube-Proxy config
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${LOADBALANCER_IP}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.pem \
    --client-key=kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}
{ # Generate Kube Controller Manager config
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.pem \
    --client-key=kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}
{ # Generate Kube-Scheduler config
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem \
    --client-key=kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}
{ # Generate Admin config
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}
} # End Generate configs

{ # Copy kubeconfigs to worker and master nodes
for instance in $WORKER_NODES; do
  scp -o StrictHostKeyChecking=no ${instance}.kubeconfig kube-proxy.kubeconfig ${instance}:~/
done

for instance in $MASTER_NODES; do
  scp -o StrictHostKeyChecking=no ${instance}.kubeconfig kube-proxy.kubeconfig admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig ${instance}:~/
done
}


{ # Generate Data Encryption Key and Config
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

# Copy Encryption config to master nodes
for instance in $MASTER_NODES; do
  scp -o StrictHostKeyChecking=no  encryption-config.yaml ${instance}:~/
done
}

{ # Setup Admin Kubeconfig via Public Address
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${LOADBALANCER_IP}:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --embed-certs=true \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin \

  kubectl config use-context kubernetes-the-hard-way

  # Export a kubeconfig to the /vagrant/ folder
    kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${LOADBALANCER_IP}:6443 \
    --kubeconfig=/vagrant/admin.kubeconfig

  kubectl config set-credentials admin \
    --embed-certs=true \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --kubeconfig=/vagrant/admin.kubeconfig

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=/vagrant/admin.kubeconfig

  kubectl config use-context kubernetes-the-hard-way --kubeconfig /vagrant/admin.kubeconfig
}
