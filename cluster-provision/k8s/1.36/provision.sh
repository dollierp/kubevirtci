#!/bin/bash

set -ex

(
  { set +e; } 2>/dev/null
  export TZ='UTC'
  date
  hwclock --get
  timedatectl status
  exit 0
)

ARCH=$(uname -m)

KUBEVIRTCI_SHARED_DIR=/var/lib/kubevirtci
mkdir -p $KUBEVIRTCI_SHARED_DIR
export ISTIO_VERSION=1.30.2
cat << EOF > $KUBEVIRTCI_SHARED_DIR/shared_vars.sh
#!/bin/bash
set -ex
export KUBELET_CGROUP_ARGS="--cgroup-driver=systemd --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"
export ISTIO_VERSION=${ISTIO_VERSION}
export ISTIO_BIN_DIR="/opt/istio-${ISTIO_VERSION}/bin"
EOF
source $KUBEVIRTCI_SHARED_DIR/shared_vars.sh

if grep -q "CentOS Stream 9" /etc/os-release; then
  release="centos9"
  ROOT_PARTITION="1"
elif grep -q "CentOS Stream 10" /etc/os-release; then
  release="centos10"
  ROOT_PARTITION="2"
else
  echo "ERROR: Could not recognize guest OS"
  exit 1
fi

# Resize root partition
dnf install -y cloud-utils-growpart
if growpart /dev/vda $ROOT_PARTITION; then
    DEVICE="/dev/vda$ROOT_PARTITION"
    MOUNTPOINT=$(findmnt -n -o TARGET "$DEVICE")
    FSTYPE=$(lsblk -no FSTYPE "$DEVICE")
    if [[ "$FSTYPE" == ext2 || "$FSTYPE" == ext3 || "$FSTYPE" == ext4 ]]; then
        echo "Resizing ext2/3/4 filesystem on $DEVICE..."
        resize2fs "$DEVICE"
    elif [[ "$FSTYPE" == xfs ]]; then
        echo "Resizing XFS filesystem on $DEVICE..."
        xfs_growfs "$MOUNTPOINT"
    else
        echo "Unsupported filesystem type: $FSTYPE"
        exit 1
    fi
fi

dnf install -y patch pciutils

systemctl stop firewalld || :
systemctl disable firewalld || :
# Make sure the firewall is never enabled again
# Enabling the firewall destroys the iptable rules
dnf -y remove firewalld

# Required for iscsi demo to work.
dnf -y install iscsi-initiator-utils

# required for some sig-network tests
dnf -y install nftables

# for rook ceph
dnf -y install lvm2
# Convince ceph our storage is fast (not a rotational disk)
echo 'ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="vd[a-z]", ATTR{queue/rotational}="0"' \
	> /etc/udev/rules.d/60-force-ssd-rotational.rules

# To prevent preflight issue related to tc not found
dnf install -y iproute-tc
# Install istioctl
export PATH="$ISTIO_BIN_DIR:$PATH"
(
  set -E
  mkdir -p "$ISTIO_BIN_DIR"
  curl -L  https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz -O
  tar -xvf ./istio-${ISTIO_VERSION}-linux-amd64.tar.gz --strip-components=2 -C ${ISTIO_BIN_DIR} istio-${ISTIO_VERSION}/bin/istioctl
  chmod +x "$ISTIO_BIN_DIR/istioctl"
)

dnf install -y container-selinux

dnf install -y libseccomp-devel

#openvswitch for s390x is not available from the centos default repos.
if [ "$ARCH" == "s390x" ]; then
  dnf install -y https://kojipkgs.fedoraproject.org//packages/openvswitch/2.16.0/2.fc36/s390x/openvswitch-2.16.0-2.fc36.s390x.rpm
  systemctl enable openvswitch
else
  dnf install -y centos-release-nfv-openvswitch
  if [ "$release" == "centos10" ]; then
    dnf install -y openvswitch3.5
  else
    dnf install -y openvswitch2.16
  fi
fi 

dnf install -y NetworkManager NetworkManager-ovs NetworkManager-config-server

# NetworkManager-config-server sets no-auto-default=* which prevents auto-DHCP
# on unconfigured interfaces. CentOS 9 has ifcfg-eth0 from cloud-init but
# CentOS 10 uses keyfile format and has no persistent connection profile.
if [ "$release" == "centos10" ]; then
  cat > /etc/NetworkManager/system-connections/eth0.nmconnection << ETHEOF
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=auto

[ipv6]
method=auto
ETHEOF
  chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection
fi

# envsubst pkg is not available by default in s390x Architecture, so explicitly installing it as part of gettext
dnf install -y gettext

# Kernel bisection
NEW_KBUILD='701'  # KO
NEW_KBUILD='691'  # OK
NEW_KBUILD='696'  # ??
NEW_KERNEL="5.14.0-${NEW_KBUILD}.el9.x86_64"  # ??
dnf install -y --disablerepo='*' \
  https://kojihub.stream.centos.org/kojifiles/packages/kernel/5.14.0/${NEW_KBUILD}.el9/x86_64/kernel-${NEW_KERNEL}.rpm \
  https://kojihub.stream.centos.org/kojifiles/packages/kernel/5.14.0/${NEW_KBUILD}.el9/x86_64/kernel-core-${NEW_KERNEL}.rpm \
  https://kojihub.stream.centos.org/kojifiles/packages/kernel/5.14.0/${NEW_KBUILD}.el9/x86_64/kernel-modules-${NEW_KERNEL}.rpm \
  https://kojihub.stream.centos.org/kojifiles/packages/kernel/5.14.0/${NEW_KBUILD}.el9/x86_64/kernel-modules-core-${NEW_KERNEL}.rpm \
  https://kojihub.stream.centos.org/kojifiles/packages/kernel/5.14.0/${NEW_KBUILD}.el9/x86_64/kernel-tools-${NEW_KERNEL}.rpm \
  https://kojihub.stream.centos.org/kojifiles/packages/kernel/5.14.0/${NEW_KBUILD}.el9/x86_64/kernel-tools-libs-${NEW_KERNEL}.rpm

dnf install -y \
  https://kojihub.stream.centos.org/kojifiles/packages/kernel/5.14.0/${NEW_KBUILD}.el9/x86_64/kernel-devel-${NEW_KERNEL}.rpm \

OLD_KERNEL=$(uname -r)
dnf remove -y --setopt=protect_running_kernel=false --disablerepo='*' \
  kernel-${OLD_KERNEL} \
  kernel-core-${OLD_KERNEL} \
  kernel-modules-${OLD_KERNEL} \
  kernel-modules-core-${OLD_KERNEL} \
  kernel-tools-${OLD_KERNEL} \
  kernel-tools-libs-${OLD_KERNEL}
