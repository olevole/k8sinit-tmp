#!/bin/sh
# part of K8S cluster CBSD plugin 2020
# CBSD Project 2013-2020
# by olevole at olevole dot ru
#
# generic controller task:
# - init k8s cluster
# - reset k8s cluster
# - init k8s master
# - export hosts file
# - modify hosts file ( -- , ++ )
# - export/show join token
# - join cluster
# - get node status
# - create pod

K8S_INIT_DIR="/var/lib/k8s"

[ ! -d ${K8S_INIT_DIR} ] && mkdir -p ${K8S_INIT_DIR}

# tpl
config_nop()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0
	date > ${_done_file}
}

config_swap()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0
	cp -a /etc/fstab /etc/fstab.bak
	swapoff -a
	sed -i  '/swap/d' /etc/fstab
	diff -ruN /etc/fstab.bak /etc/fstab
	date > ${_done_file}
}


config_hosts()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0
	local my_ip=$( hostname -I | awk '{printf $1}' )
	local my_fqdn=$( hostname )
	local my_hostname=$( hostname -s )

	my_hosts_str="${my_ip} ${my_fqdn}"

	[ "${my_fqdn}" != "${my_hostname}" ] && my_hosts_str="${my_hosts_str} ${my_hostname}"

	cp -a /etc/hosts /etc/hosts.bak
	sed -i "/${my_ip}/d" /etc/hosts
	cat >> /etc/hosts <<EOF
${my_hosts_str}		# configured by k8s-init
EOF

	diff -ruN /etc/hosts.bak /etc/hosts
}


# todo - no hardcode to release name
# todo - no interactive key
config_apt()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0

	echo 'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable' >> /etc/apt/sources.list
	echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' >> /etc/apt/sources.list

	wget -qO - https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	wget -qO - https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

	apt update -y;
	date > ${_done_file}
}

config_packages()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0

	apt install -y python-apt \
	apt-transport-https \
	ca-certificates \
	curl \
	gnupg-agent \
	software-properties-common

	#apt install -y docker-ce # lol: ( [WARNING IsDockerSystemdCheck]: detected "cgroupfs" as the Docker cgroup driver. The recommended driver is "systemd". Please follow the guide at https://kubernetes.io/docs/setup/cri/ )
	apt install -y docker-ce=18.06.2~ce~3-0~ubuntu

	update-alternatives --set iptables /usr/sbin/iptables-legacy
	update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
	update-alternatives --set arptables /usr/sbin/arptables-legacy
	update-alternatives --set ebtables /usr/sbin/ebtables-legacy

	# apt remove -y firewalld
	apt install -y kubelet kubeadm kubectl
	date > ${_done_file}
}

config_user()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0
	useradd -m -s /bin/bash -U kubeadmin
	usermod -a -G sudo kubeadmin
	date > ${_done_file}

	chown -R kubeadmin:kubeadmin ${K8S_INIT_DIR}
	chmod 0770 ${K8S_INIT_DIR}
}

# $pod_network_cidr required
config_kubeadm_init()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0

	[ -z "${pod_network_cidr}" ] && echo "pod_network_cidr" && exit 1
	kubeadm init --pod-network-cidr=${pod_network_cidr} > ${K8S_INIT_DIR}/cluster_initialized.txt

	date > ${_done_file}
}

config_kubeadm_config()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0

	if [ ! -d /home/kubeadmin ]; then
		mkdir /home/kubeadmin
		chown kubeadmin:kubeadmin /home/kubeadmin
	fi

	mkdir -p /home/kubeadmin/.kube
	cp /etc/kubernetes/admin.conf /home/kubeadmin/.kube/config
	chown -R kubeadmin:kubeadmin /home/kubeadmin/.kube
	date > ${_done_file}
}

config_kubeadm_calico()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0
	chown -R kubeadmin:kubeadmin ${K8S_INIT_DIR}
	chmod 0770 ${K8S_INIT_DIR}

	su - kubeadmin -c /bin/sh <<EOF
	kubectl apply -f https://docs.projectcalico.org/v3.11/manifests/calico.yaml > ${K8S_INIT_DIR}/pod_network_setup.txt
EOF
	_ret=$?
	echo ${_ret}
	date > ${_done_file}
}

config_kubeadm_export_token()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0

	if [ -r ${K8S_INIT_DIR}/join_token.txt ]; then
		cat ${K8S_INIT_DIR}/join_token.txt
		return 0
	fi

	su - kubeadmin -c /bin/sh <<EOF
	kubeadm token create --print-join-command 2>/dev/null > ${K8S_INIT_DIR}/join_token.txt
EOF
	_ret=$?

	cat ${K8S_INIT_DIR}/join_token.txt
}

config_join()
{
	local _done_file="${K8S_INIT_DIR}/${stage}.done"

	[ -r ${_done_file} ] && return 0

	if [ -r ${K8S_INIT_DIR}/joined.txt ]; then
		cat ${K8S_INIT_DIR}/joined.txt
		return 0
	fi

	# exported token
	#kubeadm join .. > ${K8S_INIT_DIR}/joined.txt
	_ret=$?
}


cluster_reset()
{
	yes | kubeadm reset
	rm -rf ${K8S_INIT_DIR}
}

cluster_get_nodes()
{
	su - kubeadmin -c /bin/sh <<EOF
kubectl get nodes
EOF
}

cluster_demo_pod()
{
	kubectl apply -f x.yaml
	kubectl exec -it shell-demo nginx -t
}

### MAIN
for i in swap hosts apt packages user; do
	stage="${i}"
	echo "Stage: ${stage}"
	config_${stage}
done

# end of mandatory general part

# client part
for i in join; do
	stage="${i}"
	echo "Stage: ${stage}"
	config_${stage}
done

exit 0		# ?client
# master part
# $pod_network_cidr required
pod_network_cidr="10.1.0.0/24"

for i in kubeadm_init kubeadm_config kubeadm_calico kubeadm_export_token; do
	stage="${i}"
	echo "Stage: ${stage}"
	config_${stage}
done
