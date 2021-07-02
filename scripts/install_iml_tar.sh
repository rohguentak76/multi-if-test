#!/bin/bash

mkdir -p /tmp/iml-install
cd /tmp/iml-install
curl -L https://github.com/whamcloud/integrated-manager-for-lustre/releases/download/v4.0.10.2/iml-4.0.10.2.tar.gz | tar zx --strip 1
yum install -y expect
./create_installer zfs
curl -O https://raw.githubusercontent.com/whamcloud/integrated-manager-for-lustre/v4.0.10.2/chroma-manager/tests/utils/install.exp
/usr/bin/expect install.exp admin "" lustre ""
