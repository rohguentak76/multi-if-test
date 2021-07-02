# -*- mode: ruby -*-
# vi: set ft=ruby :

# Mem in Mib allocated to each server VM
NODE_MEM = (ENV['NODE_MEM'] || 6144).freeze
# Num CPUs allocated to each server VM
NODE_CPU = (ENV['NODE_CPU'] || 8).freeze

# Mem in Mib allocated to the iSCSI server VM
ISCSI_MEM = (ENV['ISCSI_MEM'] || 1024).freeze
# Num CPUs allocated to the iSCSI server VM
ISCSI_CPU = (ENV['ISCSI_CPU'] || 4).freeze

# User is required (default to root)
# need either password or sshkey (or will assume sshkey)
VBOX_USER   = (ENV['VBOX_USER']   || "root").freeze
VBOX_PASSWD = (ENV['VBOX_PASSWD'] || "").freeze
VBOX_SSHKEY = (ENV['VBOX_SSHKEY'] || "").freeze

# Lustre version
LUSTRE = (ENV['LUSTRE'] || "2.12.4").freeze

REPO_URI = (ENV['REPO_URI'] || '').freeze

require 'open3'
require 'fileutils'

# Create a set of /24 networks under a single /16 subnet range
SUBNET_PREFIX = '10.73'.freeze

# Management network for admin comms
MGMT_NET_PFX = "#{SUBNET_PREFIX}.10".freeze

# Lustre / HPC network
LNET_PFX = "#{SUBNET_PREFIX}.20".freeze

ISCI_IP = "#{SUBNET_PREFIX}.40.10".freeze

ISCI_IP2 = "#{SUBNET_PREFIX}.50.10".freeze

Vagrant.configure('2') do |config|
  #config.vm.box = 'centos/7.7'
  #config.vm.box_url = 'http://cloud.centos.org/centos/7/vagrant/x86_64/images/CentOS-7-x86_64-Vagrant-2001_01.VirtualBox.box'
  #config.vm.box_download_checksum = 'e1a26038fb036ab8e76a6a4dfcd49856'
  #config.vm.box_download_checksum_type = 'md5'
  #config.vm.box = "revvops/centos7.6.1810"
  config.vm.box = 'centos/7'
  config.vm.box_version = '1811.01'
  #config.disksize.size = '100GB'
  config.vm.provider 'virtualbox' do |vbx|
    vbx.linked_clone = true
    vbx.memory = NODE_MEM
    vbx.cpus = NODE_CPU
    vbx.customize ['modifyvm', :id, '--audio', 'none']
  end

  # Create a basic hosts file for the VMs.
  open('hosts', 'w') do |f|
    f.puts <<-__EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

#{MGMT_NET_PFX}.9 b.local b
#{MGMT_NET_PFX}.10 adm.local adm
#{MGMT_NET_PFX}.11 mds1.local mds1
#{MGMT_NET_PFX}.12 mds2.local mds2
#{MGMT_NET_PFX}.21 oss1.local oss1
#{MGMT_NET_PFX}.22 oss2.local oss2
    __EOF
    (1..8).each do |cidx|
      f.puts "#{MGMT_NET_PFX}.3#{cidx} client#{cidx}.local client#{cidx}\n"
    end
  end

  provision_yum_updates config

  use_vault_7_6_1810 config

  config.vm.provision 'shell', inline: 'cp -f /vagrant/hosts /etc/hosts'

  config.vm.provision 'shell', path: './scripts/disable_selinux.sh'

  system("ssh-keygen -t rsa -m PEM -N '' -f id_rsa") unless File.exist?('id_rsa')

  config.vm.provision 'ssh', type: 'shell', path: './scripts/key_config.sh'

  config.vm.provision 'deps', type: 'shell', inline: <<-SHELL
    # If there is a newer EPEL available, we first need to install EPEL
    yum install -y epel-release
    # Then clean metadata (due to non-matching metalinks)
    yum clean all
    # Then recognize the new version
    yum check-update epel-release
    # Then install the new version
    yum install -y epel-release
    yum clean all
    yum install -y jq htop vim
  SHELL

  config.vm.define 'iscsi' do |iscsi|
    iscsi.vm.hostname = 'iscsi.local'

    iscsi.vm.provider 'virtualbox' do |vbx|
      vbx.memory = ISCSI_MEM
      vbx.cpus = ISCSI_CPU
    end

    iscsi.vm.provision "file",
                       source: "./99-external-storage.rules",
                       destination: "/tmp/99-external-storage.rules"

    iscsi.vm.provision 'udev-trigger', type: 'shell', inline: <<-SHELL
      mv /tmp/99-external-storage.rules /etc/udev/rules.d/ 
      udevadm trigger --subsystem-match=block
    SHELL

    provision_iscsi_net iscsi, '10'

    iscsi.vm.provider 'virtualbox' do |vbx|
      name = get_vm_name('iscsi')
      create_iscsi_disks(vbx, name)
    end

    iscsi.vm.provision 'bootstrap',
                       type: 'shell',
                       path: './scripts/bootstrap_iscsi.sh',
                       args: [ISCI_IP, ISCI_IP2]
  end

  #
  # Create an admin server for the cluster
  #
  config.vm.define 'adm', primary: true do |adm|
    adm.vm.hostname = 'adm.local'
    adm.disksize.size = '100GB'
    adm.vm.network 'forwarded_port', guest: 5432, host: 8432
    adm.vm.network 'forwarded_port', guest: 443, host: 8443
    adm.vm.network 'forwarded_port', guest: 7443, host: 7443
    adm.vm.network 'forwarded_port', guest: 5672, host: 8672

    # Admin / management network
    provision_mgmt_net adm, '10'

    configure_docker_network adm

    provision_fence_agents adm

    provision_clush adm

    create_iml_diagnostics adm

      adm.vm.synced_folder '../',
                           '/integrated-manager-for-lustre/',
                           type: 'rsync',
                           rsync__exclude: [
                              '_topdir/',
                              '.cargo/',
                              '.env',
                              '.git/',
                              'iml-gui/crate/.cargo/',
                              'iml-gui/crate/target/',
                              'iml-gui/node_modules/',
                              'target/',
                              'vagrant/'
                           ]

    # Install IML onto the admin node
    # Using a given repouri
    adm.vm.provision 'install-iml-repouri',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml_repouri.sh',
                     env: {"REPO_URI" => REPO_URI}


    # Install IML onto the admin node
    # Using the mfl devel repo
    adm.vm.provision 'install-iml-devel',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml.sh',
                     args: 'https://github.com/whamcloud/integrated-manager-for-lustre/releases/download/6.next/chroma_support.repo'

    # Install IML 5.0 onto the admin node
    # Using the mfl 5.0 repo
    adm.vm.provision 'install-iml-5',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml.sh',
                     args: 'https://raw.githubusercontent.com/whamcloud/integrated-manager-for-lustre/v5.0.0/chroma_support.repo'

    # Install IML 5.1 onto the admin node
    # Using the mfl 5.1 repo
    adm.vm.provision 'install-iml-5.1',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml.sh',
                     args: 'https://github.com/whamcloud/integrated-manager-for-lustre/releases/download/v5.1.0/chroma_support.repo'

    # Install IML 6.0 onto the admin node
    # Using the mfl 6.0 repo
    adm.vm.provision 'install-iml-6.0',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml.sh',
                     args: 'https://github.com/whamcloud/integrated-manager-for-lustre/releases/download/v6.0.0/chroma_support.repo'

    # Install IML 6.1 onto the admin node
    # Using the mfl 6.1 repo
    adm.vm.provision 'install-iml-6.1',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml.sh',
                     args: 'https://github.com/whamcloud/integrated-manager-for-lustre/releases/download/v6.1.0/chroma_support.repo'

    # Install IML 6.2 onto the admin node
    # Using the mfl 6.2 repo
    adm.vm.provision 'install-iml-6.2',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml.sh',
                     args: 'https://github.com/whamcloud/integrated-manager-for-lustre/releases/download/v6.2.0/chroma_support.repo'

    # Install IML 6.3 onto the admin node
    # Using the mfl 6.3 repo
    adm.vm.provision 'install-iml-6.3',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml.sh',
                     args: 'https://github.com/whamcloud/integrated-manager-for-lustre/releases/download/v6.3.0/chroma_support.repo'

    # Install IML 4.0.10.x onto the admin node
    # Using the mfl 4.0.10 copr repo
    adm.vm.provision 'install-iml-4.0.10',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml_tar.sh',
                     args: '4.0.10.2'

    # Install IML onto the admin node
    # This requires you have the IML source tree available at
    # /integrated-manager-for-lustre
    adm.vm.provision 'install-iml-local',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml_local.sh'

    # Install iml-docker onto the admin node
    adm.vm.provision 'install-iml-docker-local',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml_docker_local.sh'

    # Install iml-docker onto the admin node
    adm.vm.provision 'install-iml-docker-repouri',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/install_iml_docker_repouri.sh',
                     env: {"REPO_URI" => REPO_URI}

    adm.vm.provision 'deploy-managed-hosts',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/deploy_hosts.sh',
                     args: 'base_managed_patchless'

    adm.vm.provision 'load-diagnostics-db',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/load-diagnostics-db.sh'

    adm.vm.provision 'build-rust-rpms',
                     type: 'shell',
                     run: 'never',
                     path: 'scripts/build_rust_rpms.sh'
  end

  #
  # Create the metadata servers (HA pair)
  #
  (1..2).each do |i|
    config.vm.define "mds#{i}" do |mds|
      mds.vm.hostname = "mds#{i}"

      mds.vm.provider 'virtualbox' do |vbx|
        vbx.name = "mds#{i}"
      end

      create_iml_diagnostics mds

      provision_lnet_net mds, "1#{i}"
      provision_lnet_net2 mds, "10#{i}" 
      # Admin / management network
      provision_mgmt_net mds, "1#{i}"

      provision_iscsi_net mds, "1#{i}"

      # Private network to simulate crossover.
      # Used exclusively as additional cluster network
      mds.vm.network 'private_network',
                     ip: "#{SUBNET_PREFIX}.230.1#{i}",
                     netmask: '255.255.255.0',
                     auto_config: false,
                     virtualbox__intnet: 'crossover-net-mds'

      provision_iscsi_client mds, 'mds', i

      provision_mpath mds

      provision_fence_agents mds

      provision_clush mds

      cleanup_storage_server mds

      mds.vm.provision 'install-iml-local',
                       type: 'shell',
                       run: 'never',
                       path: './scripts/install_iml_local_agent.sh'

      install_lustre_zfs mds

      install_lustre_ldiskfs mds

      install_zfs_no_iml mds

      install_ldiskfs_no_iml mds

      configure_lustre_network mds

      configure_docker_network mds

      configure_ntp mds

      wait_for_ntp mds

      if i == 1
        mds.vm.provision 'create-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           genhostid
                           zpool create mgt -o multihost=on /dev/mapper/mpatha
                           zpool create mdt0 -o multihost=on /dev/mapper/mpathb
                         SHELL

        mds.vm.provision 'import-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           zpool import mgt
                           zpool import mdt0
                         SHELL

        mds.vm.provision 'zfs-params',
                         type: 'shell',
                         run: 'never',
                         path: './scripts/zfs_params.sh'

        mds.vm.provision 'create-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkfs.lustre --servicenode 10.73.20.11@tcp:10.73.20.12@tcp --mgs --backfstype=zfs mgt/mgt
                           mkfs.lustre --reformat --failover 10.73.20.12@tcp --mdt --backfstype=zfs --fsname=zfsmo --index=0 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp mdt0/mdt0
                         SHELL

        mds.vm.provision 'mount-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkdir -p /lustre/zfsmo/{mgs,mdt0}
                           mount -t lustre mgt/mgt /lustre/zfsmo/mgs
                           mount -t lustre mdt0/mdt0 /lustre/zfsmo/mdt0
                         SHELL

        mds.vm.provision 'create-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                              mkfs.lustre --mgs --reformat --servicenode=10.73.20.11@tcp --servicenode=10.73.20.12@tcp /dev/mapper/mpatha
                              mkfs.lustre --mdt --reformat --servicenode=10.73.20.11@tcp --servicenode=10.73.20.12@tcp --index=0 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp --fsname=fs /dev/mapper/mpathb
                         SHELL

        mds.vm.provision 'mount-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkdir -p /mnt/{mgs,mdt0}
                           mount -t lustre /dev/mapper/mpatha /mnt/mgs
                           mount -t lustre /dev/mapper/mpathb /mnt/mdt0
                         SHELL

        mds.vm.provision 'create-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_lvm_fs.sh',
                         args: ['fs', '/dev/mapper/mpathb', 0, '/dev/mapper/mpatha']

        mds.vm.provision 'mount-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkdir -p /mnt/mgs
                           mkdir -p /mnt/mdt0
                           mount -t lustre /dev/mapper/mgt_vg-mgt /mnt/mgs
                           mount -t lustre /dev/mapper/mdt0_vg-mdt /mnt/mdt0
                         SHELL

         mds.vm.provision 'ha-ldiskfs-lvm-fs-setup',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_lvm_mds_ha_setup.sh',
                         args: [ VBOX_USER, VBOX_PASSWD, VBOX_SSHKEY ]
      else
        mds.vm.provision 'create-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           genhostid
                           zpool create mdt1 -o multihost=on /dev/mapper/mpathc
                         SHELL

        mds.vm.provision 'import-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           zpool import mdt1
                         SHELL

        mds.vm.provision 'zfs-params',
                         type: 'shell',
                         run: 'never',
                         path: './scripts/zfs_params.sh'

        mds.vm.provision 'create-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkfs.lustre --failover 10.73.20.11@tcp --mdt --backfstype=zfs --fsname=zfsmo --index=1 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp mdt1/mdt1
                         SHELL

        mds.vm.provision 'mount-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkdir -p /lustre/zfsmo/mdt1
                           mount -t lustre mdt1/mdt1 /lustre/zfsmo/mdt1
                         SHELL

        mds.vm.provision 'create-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                            mkfs.lustre --mdt --reformat --servicenode=10.73.20.11@tcp --servicenode=10.73.20.12@tcp --index=1 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp --fsname=fs /dev/mapper/mpathc
                         SHELL

        mds.vm.provision 'create-ldiskfs-fs2',
                            type: 'shell',
                            run: 'never',
                            inline: <<-SHELL
                              mkfs.lustre --mdt --reformat --servicenode=10.73.20.11@tcp --servicenode=10.73.20.12@tcp --index=0 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp --fsname=fs2 /dev/mapper/mpathd
                            SHELL

        mds.vm.provision 'mount-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkdir -p /mnt/mdt1
                           mount -t lustre /dev/mapper/mpathc /mnt/mdt1
                         SHELL

        mds.vm.provision 'mount-ldiskfs-fs2',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkdir -p /mnt/mdt2
                           mount -t lustre /dev/mapper/mpathd /mnt/mdt2
                         SHELL

        mds.vm.provision 'create-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_lvm_fs.sh',
                         args: ['fs', '/dev/mapper/mpathc', 1, '']

        mds.vm.provision 'mount-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           mkdir -p /mnt/mdt1
                           mount -t lustre /dev/mapper/mdt1_vg-mdt /mnt/mdt1
                         SHELL

      end

      mds.vm.provision 'ha-ldiskfs-lvm-fs-prep',
                       type: 'shell',
                       run: 'never',
                       inline: <<-SHELL
                         yum -y  --nogpgcheck install pcs lustre-resource-agents
                         echo -n lustre | passwd --stdin hacluster
                         systemctl enable --now pcsd
                         mkdir -p /mnt/mgs
                         mkdir -p /mnt/mdt{0,1}
                       SHELL

      mds.vm.provision 'enable-debug',
                       type: 'shell',
                       run: 'never',
                       path: 'scripts/enable_debug.sh'
    end
  end

  #
  # Create the object storage servers (OSS)
  # Servers are configured in HA pairs
  #
  (1..4).each do |i|
    config.vm.define "oss#{i}",
                     autostart: i <= 2 do |oss|

      oss.vm.hostname = "oss#{i}"

      oss.vm.provider 'virtualbox' do |vbx|
        vbx.name = "oss#{i}"
      end

      create_iml_diagnostics oss

      # Lustre / application network
      provision_lnet_net oss, "2#{i}"
      provision_lnet_net2 oss, "20#{i}"
      # Admin / management network
      provision_mgmt_net oss, "2#{i}"

      provision_iscsi_net oss, "2#{i}"

      # Private network to simulate crossover.
      # Used exclusively as additional cluster network
      oss.vm.network 'private_network',
                     ip: "#{SUBNET_PREFIX}.231.2#{i}",
                     netmask: '255.255.255.0',
                     auto_config: false,
                     virtualbox__intnet: 'crossover-net-oss'

      provision_iscsi_client oss, 'oss', i

      provision_mpath oss

      provision_fence_agents oss

      provision_clush oss

      cleanup_storage_server oss

      oss.vm.provision 'install-iml-local',
            type: 'shell',
            run: 'never',
            path: './scripts/install_iml_local_agent.sh'

      install_lustre_zfs oss

      install_lustre_ldiskfs oss

      install_ldiskfs_no_iml oss

      install_zfs_no_iml oss

      configure_lustre_network oss

      configure_docker_network oss

      configure_ntp oss

      wait_for_ntp oss

      if i == 1
        oss.vm.provision 'create-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           genhostid
                           zpool create ost0 -o multihost=on /dev/mapper/mpatha
                           zpool create ost1 -o multihost=on /dev/mapper/mpathb
                           zpool create ost2 -o multihost=on /dev/mapper/mpathc
                           zpool create ost3 -o multihost=on /dev/mapper/mpathd
                           zpool create ost4 -o multihost=on /dev/mapper/mpathe
                           zpool create ost5 -o multihost=on /dev/mapper/mpathf
                           zpool create ost6 -o multihost=on /dev/mapper/mpathg
                           zpool create ost7 -o multihost=on /dev/mapper/mpathh
                           zpool create ost8 -o multihost=on /dev/mapper/mpathi
                           zpool create ost9 -o multihost=on /dev/mapper/mpathj
                         SHELL

        oss.vm.provision 'import-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           zpool import ost0
                           zpool import ost1
                           zpool import ost2
                           zpool import ost3
                           zpool import ost4
                           zpool import ost5
                           zpool import ost6
                           zpool import ost7
                           zpool import ost8
                           zpool import ost9
                         SHELL

        oss.vm.provision 'zfs-params',
                         type: 'shell',
                         run: 'never',
                         path: './scripts/zfs_params.sh'

        oss.vm.provision 'create-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=0 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost0/ost0
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=1 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost1/ost1
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=2 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost2/ost2
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=3 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost3/ost3
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=4 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost4/ost4
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=5 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost5/ost5
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=6 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost6/ost6
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=7 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost7/ost7
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=8 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost8/ost8
                              mkfs.lustre --failover 10.73.20.22@tcp --ost --backfstype=zfs --fsname=zfsmo --index=9 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost9/ost9
                         SHELL

         oss.vm.provision 'mount-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                              mkdir -p /lustre/zfsmo/ost{0..9}
                              mount -t lustre ost0/ost0 /lustre/zfsmo/ost0
                              mount -t lustre ost1/ost1 /lustre/zfsmo/ost1
                              mount -t lustre ost2/ost2 /lustre/zfsmo/ost2
                              mount -t lustre ost3/ost3 /lustre/zfsmo/ost3
                              mount -t lustre ost4/ost4 /lustre/zfsmo/ost4
                              mount -t lustre ost5/ost5 /lustre/zfsmo/ost5
                              mount -t lustre ost6/ost6 /lustre/zfsmo/ost6
                              mount -t lustre ost7/ost7 /lustre/zfsmo/ost7
                              mount -t lustre ost8/ost8 /lustre/zfsmo/ost8
                              mount -t lustre ost9/ost9 /lustre/zfsmo/ost9
                         SHELL

        oss.vm.provision 'create-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_fs_osts.sh',
                         args: ['a', 'e', 0, 'fs']

        oss.vm.provision 'mount-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                          mkdir -p /mnt/ost{0,1,2,3,4}
                          mount -t lustre /dev/mapper/mpatha /mnt/ost0
                          mount -t lustre /dev/mapper/mpathb /mnt/ost1
                          mount -t lustre /dev/mapper/mpathc /mnt/ost2
                          mount -t lustre /dev/mapper/mpathd /mnt/ost3
                          mount -t lustre /dev/mapper/mpathe /mnt/ost4
                         SHELL

        oss.vm.provision 'create-ldiskfs-fs2',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_fs_osts.sh',
                         args: ['f', 'j', 0, 'fs2']

        oss.vm.provision 'mount-ldiskfs-fs2',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                          mkdir -p /mnt/ost2-{0,1,2,3,4}
                          mount -t lustre /dev/mapper/mpathf /mnt/ost2-0
                          mount -t lustre /dev/mapper/mpathg /mnt/ost2-1
                          mount -t lustre /dev/mapper/mpathh /mnt/ost2-2
                          mount -t lustre /dev/mapper/mpathi /mnt/ost2-3
                          mount -t lustre /dev/mapper/mpathj /mnt/ost2-4
                         SHELL

        oss.vm.provision 'create-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_fs_osts.sh',
                         args: ['a', 'e', 0, 'fs']

        oss.vm.provision 'mount-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                          mkdir -p /mnt/ost{0,1,2,3,4}
                          mount -t lustre /dev/mapper/mpatha /mnt/ost0
                          mount -t lustre /dev/mapper/mpathb /mnt/ost1
                          mount -t lustre /dev/mapper/mpathc /mnt/ost2
                          mount -t lustre /dev/mapper/mpathd /mnt/ost3
                          mount -t lustre /dev/mapper/mpathe /mnt/ost4
                         SHELL

        oss.vm.provision 'ha-ldiskfs-lvm-fs-setup',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_lvm_oss_ha_setup.sh',
                         args: [ "{a..e} {k..o}", 0, VBOX_USER, VBOX_PASSWD, VBOX_SSHKEY ]
                         
      else
        oss.vm.provision 'create-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           genhostid
                           zpool create ost10 -o multihost=on /dev/mapper/mpathk
                           zpool create ost11 -o multihost=on /dev/mapper/mpathl
                           zpool create ost12 -o multihost=on /dev/mapper/mpathm
                           zpool create ost13 -o multihost=on /dev/mapper/mpathn
                           zpool create ost14 -o multihost=on /dev/mapper/mpatho
                           zpool create ost15 -o multihost=on /dev/mapper/mpathp
                           zpool create ost16 -o multihost=on /dev/mapper/mpathq
                           zpool create ost17 -o multihost=on /dev/mapper/mpathr
                           zpool create ost18 -o multihost=on /dev/mapper/mpaths
                           zpool create ost19 -o multihost=on /dev/mapper/mpatht
                         SHELL

        oss.vm.provision 'import-pools',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                           zpool import ost10
                           zpool import ost11
                           zpool import ost12
                           zpool import ost13
                           zpool import ost14
                           zpool import ost15
                           zpool import ost16
                           zpool import ost17
                           zpool import ost18
                           zpool import ost19
                         SHELL

        oss.vm.provision 'zfs-params',
                         type: 'shell',
                         run: 'never',
                         path: './scripts/zfs_params.sh'

        oss.vm.provision 'create-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=10 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost10/ost10
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=11 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost11/ost11
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=12 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost12/ost12
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=13 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost13/ost13
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=14 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost14/ost14
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=15 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost15/ost15
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=16 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost16/ost16
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=17 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost17/ost17
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=18 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost18/ost18
                              mkfs.lustre --failover 10.73.20.21@tcp --ost --backfstype=zfs --fsname=zfsmo --index=19 --mgsnode=10.73.20.11@tcp:10.73.20.12@tcp ost19/ost19
                         SHELL

        oss.vm.provision 'mount-zfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                              mkdir -p /lustre/zfsmo/ost{10..19}
                              mount -t lustre ost10/ost10 /lustre/zfsmo/ost10
                              mount -t lustre ost11/ost11 /lustre/zfsmo/ost11
                              mount -t lustre ost12/ost12 /lustre/zfsmo/ost12
                              mount -t lustre ost13/ost13 /lustre/zfsmo/ost13
                              mount -t lustre ost14/ost14 /lustre/zfsmo/ost14
                              mount -t lustre ost15/ost15 /lustre/zfsmo/ost15
                              mount -t lustre ost16/ost16 /lustre/zfsmo/ost16
                              mount -t lustre ost17/ost17 /lustre/zfsmo/ost17
                              mount -t lustre ost18/ost18 /lustre/zfsmo/ost18
                              mount -t lustre ost19/ost19 /lustre/zfsmo/ost19
                         SHELL

        oss.vm.provision 'create-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_fs_osts.sh',
                         args: ['k', 'o', 5, 'fs']

        oss.vm.provision 'mount-ldiskfs-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                             mkdir -p /mnt/ost{5,6,7,8,9}
                             mount -t lustre /dev/mapper/mpathk /mnt/ost5
                             mount -t lustre /dev/mapper/mpathl /mnt/ost6
                             mount -t lustre /dev/mapper/mpathm /mnt/ost7
                             mount -t lustre /dev/mapper/mpathn /mnt/ost8
                             mount -t lustre /dev/mapper/mpatho /mnt/ost9
                         SHELL

        oss.vm.provision 'create-ldiskfs-fs2',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_fs_osts.sh',
                         args: ['p', 't', 5, 'fs2']

        oss.vm.provision 'mount-ldiskfs-fs2',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                             mkdir -p /mnt/ost2-{5,6,7,8,9}
                             mount -t lustre /dev/mapper/mpathp /mnt/ost2-5
                             mount -t lustre /dev/mapper/mpathq /mnt/ost2-6
                             mount -t lustre /dev/mapper/mpathr /mnt/ost2-7
                             mount -t lustre /dev/mapper/mpaths /mnt/ost2-8
                             mount -t lustre /dev/mapper/mpatht /mnt/ost2-9
                         SHELL

        oss.vm.provision 'create-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/create_ldiskfs_fs_osts.sh',
                         args: ['k', 'o', 5, 'fs']

        oss.vm.provision 'mount-ldiskfs-lvm-fs',
                         type: 'shell',
                         run: 'never',
                         inline: <<-SHELL
                             mkdir -p /mnt/ost{5,6,7,8,9}
                             mount -t lustre /dev/mapper/mpathk /mnt/ost5
                             mount -t lustre /dev/mapper/mpathl /mnt/ost6
                             mount -t lustre /dev/mapper/mpathm /mnt/ost7
                             mount -t lustre /dev/mapper/mpathn /mnt/ost8
                             mount -t lustre /dev/mapper/mpatho /mnt/ost9
                         SHELL

      end

      oss.vm.provision 'ha-ldiskfs-lvm-fs-prep',
                       type: 'shell',
                       run: 'never',
                       inline: <<-SHELL
                         yum -y --nogpgcheck install pcs lustre-resource-agents
                         echo -n lustre | passwd --stdin hacluster
                         systemctl enable --now pcsd
                         mkdir -p /mnt/ost{0..9}
                       SHELL

      oss.vm.provision 'enable-debug',
                       type: 'shell',
                       run: 'never',
                       path: 'scripts/enable_debug.sh'
    end
  end

  # Create a set of compute nodes.
  # By default, only 2 compute nodes are created.
  # The configuration supports a maximum of 8 compute nodes.
  (1..8).each do |i|
    config.vm.define "client#{i}",
                     autostart: i <= 2 do |c|
      c.vm.hostname = "client#{i}.local"

      # Admin / management network
      provision_mgmt_net c, "3#{i}"

      # Lustre / application network
      provision_lnet_net c, "3#{i}"
      provision_lnet_net2 c, "13#{i}"
      configure_docker_network c

      configure_ntp c

      provision_clush c

      c.vm.provision 'install-iml-local',
            type: 'shell',
            run: 'never',
            path: './scripts/install_iml_local_agent.sh'

      c.vm.provision 'install-lustre-client',
                     type: 'shell',
                     run: 'never',
                     inline: <<-SHELL
                            yum-config-manager --add-repo https://downloads.whamcloud.com/public/lustre/lustre-#{LUSTRE}/el7/client/
                            yum install -y --nogpgcheck lustre-client
                     SHELL

      c.vm.provision 'configure-lustre-client-network',
                      type: 'shell',
                      run: 'never',
                      path: './scripts/configure_lustre_network.sh'
      c.vm.provision 'enable-debug',
                       type: 'shell',
                       run: 'never',
                       path: 'scripts/enable_debug.sh'

      c.vm.provision 'mount-lustre-client',
                      type: 'shell',
                      run: 'never',
                      path: './scripts/mount_lustre_client.sh'

      c.vm.provision 'mount-lustre-client-fs2',
                      type: 'shell',
                      run: 'never',
                      path: './scripts/mount_lustre_client.sh',
                      args: 'fs2'

      c.vm.provision 'mount-lustre-client-zfs',
                      type: 'shell',
                      run: 'never',
                      path: './scripts/mount_lustre_client.sh',
                      args: 'zfsmo'

    end
  end
end

def provision_iscsi_net(config, num)
  config.vm.network 'private_network',
                    ip: "#{SUBNET_PREFIX}.40.#{num}",
                    netmask: '255.255.255.0',
                    virtualbox__intnet: 'iscsi-net'

  config.vm.network 'private_network',
                    ip: "#{SUBNET_PREFIX}.50.#{num}",
                    netmask: '255.255.255.0',
                    virtualbox__intnet: 'iscsi-net'
end

def provision_lnet_net(config, num)
  config.vm.network 'private_network',
                    ip: "#{LNET_PFX}.#{num}",
                    netmask: '255.255.255.0',
                    virtualbox__intnet: 'lnet-net'
end

def provision_lnet_net2(config, num)
  config.vm.network 'private_network',
		    ip: "#{LNET_PFX}.#{num}",
		    netmask: '255.255.255.0',
		    virtualbox__intnet: 'lnet-net'
end

module OS
  def OS.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RbConfig::CONFIG["host_os"]) != nil
  end

  def OS.mac?
    (/darwin/ =~ RbConfig::CONFIG["host_os"]) != nil
  end

  def OS.unix?
    !OS.windows?
  end

  def OS.linux?
    OS.unix? and not OS.mac?
  end
end

def provision_mgmt_net(config, num)
  interface_name = if OS.windows? then 'VirtualBox Host-Only Ethernet Adapter' else 'vboxnet0' end
  
  config.vm.network 'private_network',
                    ip: "#{MGMT_NET_PFX}.#{num}",
                    netmask: '255.255.255.0',
                    name: interface_name,
                    nm_controlled: false

end

def provision_mpath(config)
  config.vm.provision 'mpath', type: 'shell', inline: <<-SHELL
    yum -y install device-mapper-multipath
    cp /usr/share/doc/device-mapper-multipath-*/multipath.conf /etc/multipath.conf
    systemctl start multipathd.service
    systemctl enable multipathd.service
  SHELL
end

def provision_fence_agents(config)
  config.vm.provision 'fence-agents', type: 'shell', inline: <<-SHELL
    yum install -y epel-release
    yum clean all
    yum install -y yum-plugin-copr
    yum -y copr enable managerforlustre/manager-for-lustre-devel
    yum install -y fence-agents-vbox
    yum -y copr disable managerforlustre/manager-for-lustre-devel
  SHELL
end

def provision_clush(config)
  config.vm.provision 'clush', type: 'shell', inline: <<-SHELL
    yum install -y epel-release
    yum clean all
    yum install -y clustershell
  SHELL

  config.vm.provision "file",
                       source: "./local.cfg",
                       destination: "/tmp/local.cfg"

  config.vm.provision "shell",
                      inline: "mv /tmp/local.cfg /etc/clustershell/groups.d/local.cfg"
end

def cleanup_storage_server(config)
  config.vm.provision 'cleanup', type: 'shell', run: 'never', inline: <<-SHELL
    yum autoremove -y chroma-agent
    rm -rf /etc/iml
    rm -rf /var/lib/{chroma,iml}
    rm -rf /etc/yum.repos.d/Intel-Lustre-Agent.repo
  SHELL
end

def provision_iscsi_client(config, name, idx)
  config.vm.provision 'iscsi-client', type: 'shell', inline: <<-SHELL
    yum -y install iscsi-initiator-utils lsscsi
    echo "InitiatorName=iqn.2015-01.com.whamcloud:#{name}#{idx}" > /etc/iscsi/initiatorname.iscsi
    iscsiadm --mode discoverydb --type sendtargets --portal #{ISCI_IP}:3260 --discover
    iscsiadm --mode node --targetname iqn.2015-01.com.whamcloud.lu:#{name} --portal #{ISCI_IP}:3260 -o update -n node.startup -v automatic
    iscsiadm --mode node --targetname iqn.2015-01.com.whamcloud.lu:#{name} --portal #{ISCI_IP}:3260 -o update -n node.conn[0].startup -v automatic
    iscsiadm --mode node --targetname iqn.2015-01.com.whamcloud.lu:#{name} --portal #{ISCI_IP2}:3260 -o update -n node.startup -v automatic
    iscsiadm --mode node --targetname iqn.2015-01.com.whamcloud.lu:#{name} --portal #{ISCI_IP2}:3260 -o update -n node.conn[0].startup -v automatic
    systemctl start iscsi
  SHELL
end

def configure_lustre_network(config)
  config.vm.provision 'configure-lustre-network',
                      type: 'shell',
                      run: 'never',
                      path: './scripts/configure_lustre_network.sh'
end

def install_lustre_zfs(config)
  config.vm.provision 'install-lustre-zfs', type: 'shell', run: 'never', inline: <<-SHELL
    yum clean all
    yum install -y --nogpgcheck lustre-zfs
    genhostid
  SHELL
end

def install_lustre_ldiskfs(config)
  config.vm.provision 'install-lustre-ldiskfs',
                      type: 'shell',
                      run: 'never',
                      inline: 'yum install -y lustre-ldiskfs'
end

def install_ldiskfs_no_iml(config)
  config.vm.provision 'install-ldiskfs-no-iml',
                      type: 'shell',
                      run: 'never',
                      reboot: true,
                      path: './scripts/install_ldiskfs_no_iml.sh',
                      args: "#{LUSTRE}"
end

def install_zfs_no_iml(config)
  config.vm.provision 'install-zfs-no-iml',
                      type: 'shell',
                      run: 'never',
                      reboot: true,
                      path: './scripts/install_zfs_no_iml.sh',
                      args: "#{LUSTRE}"
end

def use_vault_7_6_1810(config)
  config.vm.provision 'use-vault-7-6-1810',
                      type: 'shell',
                      run: 'always',
                      path: './scripts/use_vault.sh',
                      args: '7.6.1810'
end

def provision_yum_updates(config)
  config.vm.provision 'yum-update',
                     type: 'shell',
                     run: 'never',
                     inline: 'yum clean metadata; yum update -y'
end

def get_machine_folder()
  out, err = Open3.capture2e('VBoxManage list systemproperties')
  raise out unless err.exitstatus.zero?

  out.split(/\n/)
      .select { |x| x.start_with? 'Default machine folder:' }
      .map { |x| x.split('Default machine folder:')[1].strip }
      .first
end

def get_vm_name(id)
  out, err = Open3.capture2e('VBoxManage list vms')
  raise out unless err.exitstatus.zero?

  path = path = File.dirname(__FILE__).split('/').last
  name = out.split(/\n/)
            .select { |x| x.start_with? "\"#{path}_#{id}" }
            .map { |x| x.tr('"', '') }
            .map { |x| x.split(' ')[0].strip }
            .first

  name
end

# Checks if a scsi controller exists.
# This is used as a predicate to create controllers,
# as vagrant does not provide this
# functionality by default.
def controller_exists(name, controller_name)
  return false if name.nil?

  out, err = Open3.capture2e("VBoxManage showvminfo #{name}")
  raise out unless err.exitstatus.zero?

  out.split(/\n/)
     .select { |x| x.start_with? 'Storage Controller Name' }
     .map { |x| x.split(':')[1].strip }
     .any? { |x| x == controller_name }
end

# Creates a SATA Controller and attaches 10 disks to it
def create_iscsi_disks(vbox, name)
  unless controller_exists(name, 'SATA Controller')
    vbox.customize ['storagectl', :id,
                    '--name', 'SATA Controller',
                    '--add', 'sata']
  end

  dir = "#{get_machine_folder()}/vdisks"
  FileUtils.mkdir_p dir unless File.directory?(dir)

  osts = (1..20).map { |x| ["OST#{x}_", '5120'] }

  [
    %w[mgt_ 512],
    %w[mdt1_ 5120],
    %w[mdt2_ 5120],
    %w[mdt3_ 5120],
  ].concat(osts).each_with_index do |(name, size), i|
    file_to_disk = "#{dir}/#{name}.vdi"
    port = (i + 1).to_s

    unless File.exist?(file_to_disk)
      vbox.customize ['createmedium',
                      'disk',
                      '--filename',
                      file_to_disk,
                      '--size',
                      size,
                      '--format',
                      'VDI',
                      '--variant',
                      'standard']
    end

    vbox.customize ['storageattach', :id,
                    '--storagectl', 'SATA Controller',
                    '--port', port,
                    '--type', 'hdd',
                    '--medium', file_to_disk,
                    '--device', '0']

    vbox.customize ['setextradata', :id,
                    "VBoxInternal/Devices/ahci/0/Config/Port#{port}/SerialNumber",
                    name.ljust(20, '0')]
  end
end

def configure_docker_network(config)
  config.vm.provision 'configure-docker-network', type: 'shell', run: 'never', inline: <<-SHELL
    echo "10.73.10.10 nginx" >> /etc/hosts
  SHELL
end

def configure_ntp(config)
  config.vm.provision 'configure-ntp',
                         type: 'shell',
                         run: 'never',
                         path: 'scripts/configure_ntp.sh',
                         args: ["adm.local"]
end

def wait_for_ntp(config)
  config.vm.provision 'wait-for-ntp',
                          type: 'shell',
                          run: 'never',
                          path: 'scripts/wait_for_ntp.sh',
                          args: ["adm.local"]
end

def create_iml_diagnostics(config)
  config.vm.provision 'create-iml-diagnostics',
                          type: 'shell',
                          run: 'never',
                          path: 'scripts/create_iml_diagnostics.sh',
                          args: ["10.73.10.1"]
end
