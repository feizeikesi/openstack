#!/bin/bash

#设置环境变量
EV=/dev/sda
MY_IP=192.168.0.155

yum install -y lvm2

systemctl enable lvm2-lvmetad.service
systemctl start lvm2-lvmetad.service

pvcreate $DEV
vgcreate cinder-volumes $DEV

cp /etc/lvm/lvm.conf{,.$(date +%s).bak}
sed -i '141a filter = [ "a/sdb2/", "r/.*/"]' /etc/lvm/lvm.conf #在141行后添加

yum install -y openstack-cinder targetcli python-keystone


cp /etc/cinder/cinder.conf{,.$(date +%s).bak}

echo '
[DEFAULT]
transport_url = rabbit://openstack:'$RABBIT_PASS'@controller
auth_strategy = keystone 
my_ip = '$MY_IP' #存储节点上管理网络接口的IP地址
enabled_backends = lvm
glance_api_servers = http://controller:9292

[database]
connection = mysql+pymysql://cinder:'$CINDER_DBPASS'@controller/cinder

[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = '$CINDER_PASS'

[lvm] 
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver 
volume_group = cinder-volumes 
iscsi_protocol = iscsi 
iscsi_helper = lioadm

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

'>/etc/cinder/cinder.conf

systemctl enable openstack-cinder-volume.service target.service
systemctl start openstack-cinder-volume.service target.service