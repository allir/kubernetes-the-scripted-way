#!/usr/bin/env bash
set -euxo pipefail

{ # RBAC for Kubelet Authorization
cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kube-apiserver
EOF
}

{ # Create boostrap token and roles for TLS bootstrapping worker nodes
BOOTSTRAP_TOKEN_EXPIRE=$(date -d "+10 years" '+%Y-%m-%dT%H:%M:%SZ')
cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: v1
kind: Secret
metadata:
  # Name MUST be of form "bootstrap-token-<token id>"
  name: bootstrap-token-${BOOTSTRAP_TOKEN_ID}
  namespace: kube-system

# Type MUST be 'bootstrap.kubernetes.io/token'
type: bootstrap.kubernetes.io/token
stringData:
  # Human readable description. Optional.
  description: "The default bootstrap token generated by 'kubeadm init'."

  # Token ID and secret. Required.
  token-id: ${BOOTSTRAP_TOKEN_ID}
  token-secret: ${BOOTSTRAP_TOKEN_SECRET}

  # Expiration. Optional.
  expiration: ${BOOTSTRAP_TOKEN_EXPIRE}

  # Allowed usages.
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"

  # Extra groups to authenticate the token as. Must start with "system:bootstrappers:"
  auth-extra-groups: system:bootstrappers:worker
EOF

cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
# enable bootstrapping nodes to create CSR
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: create-csrs-for-bootstrapping
subjects:
- kind: Group
  name: system:bootstrappers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:node-bootstrapper
  apiGroup: rbac.authorization.k8s.io
EOF

cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
# Approve all CSRs for the group "system:bootstrappers"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: auto-approve-csrs-for-group
subjects:
- kind: Group
  name: system:bootstrappers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
  apiGroup: rbac.authorization.k8s.io
EOF

cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
# Approve renewal CSRs for the group "system:nodes"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: auto-approve-renewals-for-nodes
subjects:
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
  apiGroup: rbac.authorization.k8s.io
EOF
}

{ # Setting up Networking and DNS
  kubectl apply --kubeconfig admin.kubeconfig -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version --kubeconfig admin.kubeconfig | base64 | tr -d '\n')&env.IPALLOC_RANGE=${CLUSTER_POD_CIDR}"
  
  curl -s https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/coredns.yaml.sed | sed -E "s/image: coredns\/coredns.*$/image: coredns\/coredns:${COREDNS_VERSION:1}/" | sed -E "s/# replicas.*$/replicas: 2/" | sed "s/CLUSTER_DNS_IP/${KUBERNETES_DNS_IP}/" | kubectl apply --kubeconfig admin.kubeconfig -f -
  # Patch the deployment to mount the hosts /etc/hosts file and serve it in the below config. Otherwise the control-plane/worker nodes are note resolvable from within the cluster pod network
  kubectl -n kube-system --kubeconfig admin.kubeconfig patch deployment coredns --patch '{"spec": {"template": {"spec": {"containers": [{"name": "coredns", "volumeMounts": [{"name": "hosts-volume", "mountPath": "/etc/hosts"}] }], "volumes": [{ "name": "hosts-volume", "hostPath": {"path": "/etc/hosts"} }] } } } }'

  cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        hosts {
          fallthrough
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
EOF
}

# Verify
kubectl get ds,deploy --output wide --namespace kube-system --kubeconfig admin.kubeconfig
