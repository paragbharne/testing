#!/bin/bash

LOG_FILE="/var/log/cloudera-azure-initialize.log"

EXECNAME=$0
ADMINUSER=$1
declare -a arrayname=($2 $3 $4)
NODETYPE="masternode"

# logs everything to the LOG_FILE
log() {
  echo "$(date) [${EXECNAME}]: $*" >> ${LOG_FILE}
}

# logs everything to the LOG_FILE
log() {
  echo "$(date) [${EXECNAME}]: $*" >> ${LOG_FILE}
}

for element in "${arrayname[@]}"
do
        line=$(echo "$element" | sed 's/:/ /' | sed 's/:/ /')
        echo "$line" >> /etc/hosts
done

log "------- initialize-node.sh starting -------"

log "EXECNAME: $EXECNAME"
log "MASTERIP: $MASTERIP"
log "WORKERIP: $WORKERIP"
log "NAMEPREFIX: $NAMEPREFIX"
log "NAMESUFFIX: $NAMESUFFIX"
log "MASTERNODES: $MASTERNODES"
log "DATANODES: $DATANODES"
log "ADMINUSER: $ADMINUSER"
log "NODETYPE: $NODETYPE"

log "Done Generate IP Addresses for the Cloudera setup. Host file looks like:"
cat /etc/hosts >> ${LOG_FILE} 2>&1

# Disable the need for a tty when running sudo and allow passwordless sudo for the admin user
sed -i '/Defaults[[:space:]]\+!*requiretty/s/^/#/' /etc/sudoers
echo "$ADMINUSER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Mount and format the attached disks base on node type
log "Mount and format the attached disks for ${NODETYPE}"
if [ "$NODETYPE" == "masternode" ]
then
  bash ./prepare-masternode-disks.sh >> ${LOG_FILE} 2>&1
elif [ "$NODETYPE" == "datanode" ]
then
  bash ./prepare-datanode-disks.sh >> ${LOG_FILE} 2>&1
else
  log "Unknown node type : ${NODETYPE}, default to datanode"
  bash ./prepare-datanode-disks.sh >> ${LOG_FILE} 2>&1
fi

log "Done preparing disks. Now 'ls -la /' looks like this:"
ls -la / >> ${LOG_FILE} 2>&1

# Create Impala scratch directory
log "Create Impala scratch directories"
numDataDirs=$(ls -la / | grep data | wc -l)
log "numDataDirs: $numDataDirs"
let endLoopIter=$((numDataDirs - 1))
for x in $(seq 0 $endLoopIter)
do
  echo mkdir -p /"data${x}"/impala/scratch
  mkdir -p /"data${x}"/impala/scratch
  chmod 777 /"data${x}"/impala/scratch
done

# Disable SELinux
log "Disable SELinux"
setenforce 0 >> /tmp/setenforce.out
cat /etc/selinux/config > /tmp/beforeSelinux.out
sed -i 's^SELINUX=enforcing^SELINUX=disabled^g' /etc/selinux/config || true
cat /etc/selinux/config > /tmp/afterSeLinux.out

# Disable iptables
log "Disable iptables"
/etc/init.d/iptables save
#/etc/init.d/iptables stop
systemctl stop firewalld
#chkconfig iptables off
systemctl disable firewalld

# Install and start NTP
log "Install and start NTP"
yum install -y ntp
service ntpd start
service ntpd status
chkconfig ntpd on

# Disable THP
log "Disable THP"
echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled
echo "echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled" | tee -a /etc/rc.local

# Set swappiness to 1
log "Set swappiness to 1"
echo vm.swappiness=1 | tee -a /etc/sysctl.conf
echo 1 | tee /proc/sys/vm/swappiness

# Set system tuning params
log "Set system tuning params"
echo net.ipv4.tcp_timestamps=0 >> /etc/sysctl.conf
echo net.ipv4.tcp_sack=1 >> /etc/sysctl.conf
echo net.core.rmem_max=4194304 >> /etc/sysctl.conf
echo net.core.wmem_max=4194304 >> /etc/sysctl.conf
echo net.core.rmem_default=4194304 >> /etc/sysctl.conf
echo net.core.wmem_default=4194304 >> /etc/sysctl.conf
echo net.core.optmem_max=4194304 >> /etc/sysctl.conf
echo net.ipv4.tcp_rmem="4096 87380 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_wmem="4096 65536 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_low_latency=1 >> /etc/sysctl.conf
sed -i "s/defaults        1 1/defaults,noatime        0 0/" /etc/fstab

# Set host FQDN
myhostname=$(hostname)
fqdnstring=$(python -c "import socket; print socket.getfqdn('$myhostname')")
log "Set host FQDN to ${fqdnstring}"
sed -i "s/.*HOSTNAME.*/HOSTNAME=${fqdnstring}/g" /etc/sysconfig/network
/etc/init.d/network restart

#disable password authentication in ssh
#sed -i "s/UsePAM\s*yes/UsePAM no/" /etc/ssh/sshd_config
#sed -i "s/PasswordAuthentication\s*yes/PasswordAuthentication no/" /etc/ssh/sshd_config
#/etc/init.d/sshd restart

log "------- initialize-node.sh succeeded -------"

# always `exit 0` on success
exit 0
