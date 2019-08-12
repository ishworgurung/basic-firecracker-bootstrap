#!/usr/bin/env bash

# sourced from https://github.com/firecracker-microvm/firecracker/tree/master/docs
set -euf -o pipefail

echo "#########################################################"
echo "make sure prerequisites are met."
echo "https://github.com/firecracker-microvm/firecracker/blob/master/docs/getting-started.md#prerequisites"
echo "make sure tmux is installed (for tty) and you have sudo superpower (for host networking setup)."
echo "###############################################################"
read

###############

# Host configs
TTY_CONSOLE=console$(( ${RANDOM} % 4 ))
DNS_IPADDR=172.19.0.2
WAN_IF=wlan0
TAP_DEV=tap0
FIRECRACKER_UDS="/tmp/firecracker.socket.${RANDOM}"

# Guest networking
GUEST_GW=172.21.0.1
GUEST_NET=172.21.0.1/24
GUEST_IPADDR=172.21.0.3

# Guest hardware
GUEST_VCPUs=2
GUEST_MEM_MiB=2048

############

arch=$(uname -m)
dest_kernel="hello-vmlinux.bin"
dest_rootfs="hello-rootfs.ext4"
image_bucket_url="https://s3.amazonaws.com/spec.ccfc.min/img"

init() {
  rm -f ${FIRECRACKER_UDS}
  tmux new-session -d -s ${TTY_CONSOLE} 
  tmux send-keys "./firecracker --api-sock ${FIRECRACKER_UDS}" C-m
  sleep 2s
} && init

get_guest_kernel_rootfs() {
  if [ ${arch} = "x86_64" ]; then
    kernel="${image_bucket_url}/hello/kernel/hello-vmlinux.bin"
    rootfs="${image_bucket_url}/hello/fsfiles/hello-rootfs.ext4"
  elif [ ${arch} = "aarch64" ]; then
    kernel="${image_bucket_url}/aarch64/ubuntu_with_ssh/kernel/vmlinux.bin"
    rootfs="${image_bucket_url}/aarch64/ubuntu_with_ssh/fsfiles/xenial.rootfs.ext4"
  else
    echo "Cannot run firecracker on $arch architecture!"
    exit 1
  fi
  echo "Downloading $kernel..."
  curl -fsSL -o $dest_kernel $kernel
  echo "Downloading $rootfs..."
  curl -fsSL -o $dest_rootfs $rootfs

  echo "Saved kernel file to $dest_kernel and root block device to $dest_rootfs."
} 

if [[ ! -f "${dest_kernel}" ]] || [[ ! -f "${dest_rootfs}" ]]; then
  get_guest_kernel_rootfs
fi

set_guest_kernel() {
  curl --unix-socket ${FIRECRACKER_UDS} -i \
    -X PUT 'http://localhost/boot-source'   \
    -H 'Accept: application/json'           \
    -H 'Content-Type: application/json'     \
    -d "{
          \"kernel_image_path\": \"${dest_kernel}\",
          \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off\"
     }"
} && set_guest_kernel

set_guest_rootfs() {
  curl --unix-socket ${FIRECRACKER_UDS} -i \
    -X PUT 'http://localhost/drives/rootfs' \
    -H 'Accept: application/json'           \
    -H 'Content-Type: application/json'     \
    -d "{
          \"drive_id\": \"rootfs\",
          \"path_on_host\": \"${dest_rootfs}\",
          \"is_root_device\": true,
          \"is_read_only\": false
     }"
} && set_guest_rootfs

set_guest_networking() {
  sudo ip link del ${TAP_DEV} || true
  sudo iptables -t nat -X
  sudo iptables -t nat -F
  sudo iptables -X
  sudo iptables -F
  sudo ip tuntap add ${TAP_DEV} mode tap
  sudo ip addr add ${GUEST_NET} dev ${TAP_DEV}
  sudo ip link set ${TAP_DEV} up
  sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
  sudo iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE
  sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  sudo iptables -A FORWARD -i ${TAP_DEV} -o ${WAN_IF} -j ACCEPT

  curl -X PUT \
  --unix-socket ${FIRECRACKER_UDS} \
  http://localhost/network-interfaces/eth0 \
  -H accept:application/json \
  -H content-type:application/json \
  -d "{
      \"iface_id\": \"eth0\",
      \"guest_mac\": \"AA:FC:00:00:00:01\",
      \"host_dev_name\": \"${TAP_DEV}\"
    }"
} && set_guest_networking

start_guest_microvm() {
  curl --unix-socket ${FIRECRACKER_UDS} -i  \
    -X PUT 'http://localhost/machine-config' \
    -H 'Accept: application/json'            \
    -H 'Content-Type: application/json'      \
    -d "{
        \"vcpu_count\": ${GUEST_VCPUs},
        \"mem_size_mib\": ${GUEST_MEM_MiB},
        \"ht_enabled\": false
    }"

  curl --unix-socket ${FIRECRACKER_UDS} -i \
    -X PUT 'http://localhost/actions'       \
    -H  'Accept: application/json'          \
    -H  'Content-Type: application/json'    \
    -d '{
        "action_type": "InstanceStart"
     }'
} && start_guest_microvm

show_setup_notes() {
  echo "[*] do the following in a different terminal window:"
  echo "[+] attach to the session"
  echo "[+] login to tty (root/root)"
  echo "[+] setup networking"
  echo "[+] to exit gracefully, type 'reboot'"
  echo "$> tmux attach -t ${TTY_CONSOLE}"
  echo "$> ip addr add ${GUEST_IPADDR} dev eth0"
  echo "$> ip link set eth0 up"
  echo "$> ip route add default via ${GUEST_GW} dev eth0 onlink"
  echo "$> echo \"nameserver ${DNS_IPADDR}\" > /etc/resolv.conf"
  echo "$> ping -c2 one.one.one.one"
} && show_setup_notes
