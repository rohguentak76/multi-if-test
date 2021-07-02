#!/bin/bash

yum-config-manager --disable base extras updates
sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.conf
yum-config-manager \
  --add-repo http://vault.centos.org/${1}/os/x86_64/ \
  --add-repo http://vault.centos.org/${1}/extras/x86_64/ \
  --add-repo http://vault.centos.org/${1}/updates/x86_64/  || true
