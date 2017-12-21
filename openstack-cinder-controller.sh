#!/bin/bash

MY_IP=192.168.0.156

source ./admin-openstack.sh || { echo "加载前面设置的admin-openstack.sh环境变量脚本";exit; }

echo '创建 cinder 数据库'

DATABASE_INIT_SQL="
#keystone cinder
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '"$CINDER_DBPASS"';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '"$CINDER_DBPASS"';

flush privileges;
select user,host from mysql.user;
show databases;
"
mysql -u root -p$DATABASE_PASS -e "${DATABASE_INIT_SQL}"
sleep 1

echo '创建 cinder 用户'
openstack user create --domain default --password=$CINDER_PASS cinder
sleep 1

echo '添加 service 项目 角色'
openstack role add --project service --user cinder admin
sleep 1

echo '创建 cinder api 服务实例'
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
sleep 1

echo '创建 cinder api 服务端'
openstack endpoint create --region RegionOne volumev2 public http://controller.yun.tidebuy:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 internal http://controller.yun.tidebuy:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 admin http://controller.yun.tidebuy:8776/v2/%\(project_id\)s

openstack endpoint create --region RegionOne volumev3 public http://controller.yun.tidebuy:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://controller.yun.tidebuy:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://controller.yun.tidebuy:8776/v3/%\(project_id\)s

echo '安装 openstack-cinder'
yum install -y openstack-cinder
sleep 1

echo '备份相关配置文件'
cp /etc/cinder/cinder.conf{,.$(date +%s).bak}
cp /etc/nova/nova.conf{,.$(date +%s).bak}

echo '配置相关配置文件'

echo '
[DEFAULT]
auth_strategy = keystone
transport_url = rabbit://openstack:'$RABBIT_PASS'@controller.yun.tidebuy
my_ip = '$MY_IP'

[database]
connection = mysql+pymysql://cinder:'$CINDER_DBPASS'@controller.yun.tidebuy/cinder

[keystone_authtoken]
auth_uri = http://controller.yun.tidebuy:5000
auth_url = http://controller.yun.tidebuy:35357
memcached_servers = controller.yun.tidebuy:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = '$CINDER_PASS'

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
'>/etc/cinder/cinder.conf

echo '
[cinder]
os_region_name = RegionOne
'>>/etc/nova/nova.conf

echo '填充 cinder 数据库'
su -s /bin/sh -c "cinder-manage db sync" cinder
sleep 1

echo '检查 cinder 数据库'
mysql -h controller.yun.tidebuy -u cinder -p$CINDER_DBPASS -e "use cinder;show tables;" 
sleep 1

echo '重启openstack-nova-api 服务'
systemctl restart openstack-nova-api.service
sleep 1

echo '启动相关服务'
systemctl enable openstack-cinder-api.service openstack-cinder-scheduler.service
systemctl start openstack-cinder-api.service openstack-cinder-scheduler.service
sleep 1

echo '检查服务是否正常'
netstat -antp|grep 8776 #cheack
cinder service-list