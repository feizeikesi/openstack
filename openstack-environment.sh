#!/bin/bash
export DATABASE_PASS=123456
export ADMIN_PASS=123456
export CINDER_DBPASS=123456
export CINDER_PASS=123456
export DASH_DBPASS=123456
export DEMO_PASS=123456
export GLANCE_DBPASS=123456
export GLANCE_PASS=123456
export KEYSTONE_DBPASS=123456
export METADATA_SECRET=123456
export NEUTRON_DBPASS=123456
export NEUTRON_PASS=123456
export NOVA_DBPASS=123456
export NOVA_PASS=123456
export PLACEMENT_PASS=123456
export RABBIT_PASS=123456


echo '安装必要环境'
yum -y install wget vim ntp net-tools tree openssh

echo '更换阿里源'
mv /etc/yum.repos.d/CentOS-Base.repo{,.bak}
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
sleep 1

echo '安装OpenStack库'
yum install centos-release-openstack-pike -y 
yum clean all && yum makecache #生成缓存
sleep 1

echo 'OpenStack客户端 openstack工具'
yum install -y python-openstackclient openstack-selinux  openstack-utils  python2-PyMySQL  

echo '修改并发数'
echo '
* soft nofile 65536  
* hard nofile 65536 
'>>/etc/security/limits.conf

echo '
fs.file-max=655350  
net.ipv4.ip_local_port_range = 1025 65000  
net.ipv4.tcp_tw_recycle = 1 
'>>/etc/sysctl.conf

sysctl -p

echo '时间同步'
/usr/sbin/ntpdate ntp6.aliyun.com
echo "*/3 * * * * /usr/sbin/ntpdate ntp6.aliyun.com  &> /dev/null" > /tmp/crontab
crontab /tmp/crontab
