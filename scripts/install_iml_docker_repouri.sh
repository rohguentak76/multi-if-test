#!/bin/bash

    cat <<EOF > /etc/yum.repos.d/manager-for-lustre.repo
[managerforlustre-manager-for-lustre-devel]
name=Copr repo for manager-for-lustre-devel owned by managerforlustre
baseurl=https://copr-be.cloud.fedoraproject.org/results/managerforlustre/manager-for-lustre-devel/epel-7-\$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://copr-be.cloud.fedoraproject.org/results/managerforlustre/manager-for-lustre-devel/pubkey.gpg
repo_gpgcheck=0
enabled=1
EOF

if [[ -n $REPO_URI ]];
then
    cat <<EOF >> /etc/yum.repos.d/manager-for-lustre.repo

[manager-for-lustre]
name=manager-for-lustre
baseurl=$REPO_URI
enabled=1
gpgcheck=0
EOF
fi

yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce
yum install -y --disablerepo managerforlustre-manager-for-lustre-devel iml-docker
systemctl enable --now docker
docker swarm init --advertise-addr=127.0.0.1 --listen-addr=127.0.0.1

# Password
echo "lustre" > /etc/iml-docker/setup/password
docker secret create iml_pw /etc/iml-docker/setup/password

    cat <<EOF > /etc/iml-docker/setup/base.repo
[managerforlustre-manager-for-lustre-devel]
name=Copr repo for manager-for-lustre-devel owned by managerforlustre
baseurl=https://copr-be.cloud.fedoraproject.org/results/managerforlustre/manager-for-lustre-devel/epel-7-\$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://copr-be.cloud.fedoraproject.org/results/managerforlustre/manager-for-lustre-devel/pubkey.gpg
repo_gpgcheck=0
enabled=1
EOF

if [[ -n $REPO_URI ]];
then
    cat <<EOF >> /etc/iml-docker/setup/base.repo

[manager-for-lustre]
name=manager-for-lustre
baseurl=$REPO_URI
enabled=1
gpgcheck=0
EOF
fi

cat <<EOF > /etc/iml-docker/docker-compose.overrides.yml
version: "3.7"

services:
  job-scheduler:
    extra_hosts:
      - "adm.local:10.73.10.10"
      - "mds1.local:10.73.10.11"
      - "mds2.local:10.73.10.12"
      - "oss1.local:10.73.10.21"
      - "oss2.local:10.73.10.22"
      - "client1.local:10.73.10.31"
    environment:
      - "NTP_SERVER_HOSTNAME=adm.local"
  iml-warp-drive:
    environment:
      - RUST_LOG=debug
  iml-action-runner:
    environment:
      - RUST_LOG=debug
  iml-api:
    environment:
      - RUST_LOG=debug
  iml-ostpool:
    environment:
      - RUST_LOG=debug
  iml-stats:
    environment:
      - RUST_LOG=debug
  iml-agent-comms:
    environment:
      - RUST_LOG=debug
  device:
    environment:
      - RUST_LOG=debug
  network:
    environment:
      - RUST_LOG=debug
EOF

# Enable but do not start iml-docker
systemctl enable iml-docker

