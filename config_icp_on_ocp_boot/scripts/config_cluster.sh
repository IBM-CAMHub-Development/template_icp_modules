#!/bin/bash

icp_master_host=$1
icp_proxy_host=$2
icp_management_host=$3
ocp_master_host=$4
ocp_vm_domain_name=$5
icp_version=$6
ocp_enable_glusterfs=$7

sudo cp /etc/origin/master/admin.kubeconfig /opt/ibm-cloud-private-rhos-${icp_version}/cluster/kubeconfig

sed -i -e '/cluster_node/,+16 d' /opt/ibm-cloud-private-rhos-${icp_version}/cluster/config.yaml

ocp_router=$(sed -n '/openshift_master_default_subdomain/p' /etc/ansible/hosts | cut -d '=' -f 2)

if [[ $ocp_enable_glusterfs == "false" ]]; then
  cat > generic-gce.yaml << EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: generic
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
  zone: us-east1-d
EOF
  oc create -f generic-gce.yaml
  oc new-project rh-eng
  cat > pvc-fast.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
 name: pvc-engineering
spec:
 accessModes:
  - ReadWriteMany
 resources:
   requests:
     storage: 35Gi
 storageClassName: generic
EOF
  oc create -f pvc-fast.yaml
fi

config_file=$(
  echo "cluster_nodes:"
  echo "  master:"
  echo "    - ${icp_master_host}.${ocp_vm_domain_name}"
  echo "  proxy:"
  echo "    - ${icp_proxy_host}.${ocp_vm_domain_name}"
  echo "  management:"
  echo "    - ${icp_management_host}.${ocp_vm_domain_name}"
  echo ""
  if [[ $ocp_enable_glusterfs == "true" ]]; then
    echo "storage_class: glusterfs-storage"
  else
    echo "storage_class: generic"
  fi
)

echo "${config_file}" >> /opt/ibm-cloud-private-rhos-${icp_version}/cluster/config.yaml

# run installer
cd /opt/ibm-cloud-private-rhos-${icp_version}/cluster
sudo docker run -t --net=host -e LICENSE=accept -v $(pwd):/installer/cluster:z -v /var/run:/var/run:z -v /etc/docker:/etc/docker:z --security-opt label:disable ibmcom/icp-inception-amd64:${icp_version}-rhel-ee install-with-openshift | tee /tmp/install.log; test $${PIPESTATUS[0]} -eq 0

# send certificate to all other nodes
scp -r /etc/docker/certs.d/docker-registry-default* root@${icp_master_host}.${ocp_vm_domain_name}:/etc/docker/certs.d
scp -r /etc/docker/certs.d/docker-registry-default* root@${icp_proxy_host}.${ocp_vm_domain_name}:/etc/docker/certs.d
scp -r /etc/docker/certs.d/docker-registry-default* root@${icp_management_host}.${ocp_vm_domain_name}:/etc/docker/certs.d