export MY_IP=10.10.0.3
export NET_NAME=em2

export DATABASE_INIT_SQL="
#keystone service
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost'  IDENTIFIED BY '"$KEYSTONE_DBPASS"';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '"$KEYSTONE_DBPASS"';

#glance service
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost'  IDENTIFIED BY '"$GLANCE_DBPASS"';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%'  IDENTIFIED BY '"$GLANCE_DBPASS"';

#nova service
CREATE DATABASE nova;
CREATE DATABASE nova_api;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '"$NOVA_DBPASS"';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '"$NOVA_DBPASS"';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '"$NOVA_DBPASS"';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '"$NOVA_DBPASS"';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '"$NOVA_DBPASS"';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '"$NOVA_DBPASS"';

#neutron service
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '"$NEUTRON_DBPASS"';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '"$NEUTRON_DBPASS"';

GRANT ALL PRIVILEGES ON *.* TO 'root'@'%'  IDENTIFIED BY '"$KEYSTONE_DBPASS"';

flush privileges;
select user,host from mysql.user;
show databases;
"


echo '安装 mariadb'
yum install mariadb mariadb-server python2-PyMySQL -y

echo "#
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
#">/etc/my.cnf.d/openstack.cnf

echo '启动数据库服务'
systemctl enable mariadb.service
systemctl start mariadb.service
netstat -antp|grep mysqld
sleep 1

echo '创建数据库及密码'
mysql -u root -p$DATABASE_PASS -e "${DATABASE_INIT_SQL}"
sleep 3

[[ -f /usr/bin/expect ]] || { yum install expect -y; } #若没expect则安装

#exp_continue 重新循环
/usr/bin/expect << EOF
set timeout 30
spawn mysql_secure_installation
expect {
    "enter for none" { send "\r"; exp_continue}
    "Y/n" { send "Y\r"; exp_continue}
    "password:" { send "$DATABASE_PASS\r"; exp_continue}
    "new password:" { send "$DATABASE_PASS\r"; exp_continue}
    eof { exit }
}
EOF

echo '安装 rabbitmq'
yum install rabbitmq-server -y

echo '启动 rabbitmq'
systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service

echo '设置 rabbitmq权限及密码'
rabbitmqctl add_user openstack $RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
rabbitmqctl  set_user_tags openstack  administrator
sleep 1
rabbitmq-plugins enable rabbitmq_management  #启动web插件端口15672

echo '安装 memcached 缓存'
yum install memcached python-memcached -y

cp /etc/sysconfig/memcached{,.$(date +%s).bak}
sed -i 's/^OPTIONS="-l 127.0.0.1,::1"/OPTIONS="-l 127.0.0.1,::1,controller.yun.tidebuy"/g'  /etc/sysconfig/memcached
cat /etc/sysconfig/memcached


echo '启动 memcached'
systemctl enable memcached.service
systemctl start memcached.service

echo '安装 Keystone'
yum install openstack-keystone httpd mod_wsgi -y
sleep 3

cp /etc/keystone/keystone.conf{,.$(date +%s).bak}

echo "#
[database]
connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@controller.yun.tidebuy/keystone
[token]
provider = fernet
#">/etc/keystone/keystone.conf

/bin/sh -c "keystone-manage db_sync" keystone

echo '检查表是否创建成功'
mysql -h controller.yun.tidebuy -ukeystone -p$KEYSTONE_DBPASS -e "use keystone;show tables;"

keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
--bootstrap-admin-url http://controller.yun.tidebuy:35357/v3/ \
--bootstrap-internal-url http://controller.yun.tidebuy:5000/v3/ \
--bootstrap-public-url http://controller.yun.tidebuy:5000/v3/ \
--bootstrap-region-id RegionOne

echo 'apache配置'
cp /etc/httpd/conf/httpd.conf{,.$(date +%s).bak}
echo "ServerName controller.yun.tidebuy">>/etc/httpd/conf/httpd.conf
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/

systemctl enable httpd.service
systemctl restart httpd.service
sleep 3
netstat -antp|egrep ':5000|:35357|:80'

echo '生成 admin 脚本'
echo "
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default 
export OS_PROJECT_NAME=admin 
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://controller.yun.tidebuy:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
">./admin-openstack.sh

echo '测试脚本是否生效'
source ./admin-openstack.sh
openstack token issue

echo '创建 default 域 用户'
openstack user create --domain default --password=$GLANCE_PASS glance
openstack user create --domain default --password=$NOVA_PASS nova
openstack user create --domain default --password=$PLACEMENT_PASS placement
openstack user create --domain default --password=$NEUTRON_PASS neutron

echo '创建 default 项目'
openstack project create --domain default --description "Service Project" service

echo '添加 service 项目权限'
openstack role add --project service --user glance admin
openstack role add --project service --user nova admin
openstack role add --project service --user placement admin
openstack role add --project service --user neutron admin

echo '创建 glance,nova,placement,neutron 服务'
openstack service create --name glance  --description "OpenStack Image" image
openstack service create --name nova --description "OpenStack Compute" compute
openstack service create --name placement --description "Placement API" placement
openstack service create --name neutron --description "OpenStack Networking" network

echo '创建服务端'
openstack endpoint create --region RegionOne image public http://controller.yun.tidebuy:9292
openstack endpoint create --region RegionOne image internal http://controller.yun.tidebuy:9292
openstack endpoint create --region RegionOne image admin http://controller.yun.tidebuy:9292

openstack endpoint create --region RegionOne compute public http://controller.yun.tidebuy:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller.yun.tidebuy:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://controller.yun.tidebuy:8774/v2.1

openstack endpoint create --region RegionOne placement public http://controller.yun.tidebuy:8778
openstack endpoint create --region RegionOne placement internal http://controller.yun.tidebuy:8778
openstack endpoint create --region RegionOne placement admin http://controller.yun.tidebuy:8778

openstack endpoint create --region RegionOne network public http://controller.yun.tidebuy:9696
openstack endpoint create --region RegionOne network internal http://controller.yun.tidebuy:9696
openstack endpoint create --region RegionOne network admin http://controller.yun.tidebuy:9696

echo '列出所有服务端'
openstack endpoint list

echo '安装 glance'
yum install openstack-glance -y

cp /etc/glance/glance-api.conf{,.$(date +%s).bak}
cp /etc/glance/glance-registry.conf{,.$(date +%s).bak}

export IMG_PATH='/data/images'
mkdir -p $IMG_PATH
chown glance:nobody $IMG_PATH
echo "镜像目录： $IMG_PATH"
echo "#
[database]
connection = mysql+pymysql://glance:$GLANCE_PASS@controller.yun.tidebuy/glance
[keystone_authtoken]
auth_uri = http://controller.yun.tidebuy:5000/v3
auth_url = http://controller.yun.tidebuy:35357/v3
memcached_servers = controller.yun.tidebuy:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = glance
password = $GLANCE_PASS
[paste_deploy]
flavor = keystone
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = $IMG_PATH
#" > /etc/glance/glance-api.conf

echo "#
[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@controller.yun.tidebuy/glance

[keystone_authtoken]
auth_uri = http://controller.yun.tidebuy:5000
auth_url = http://controller.yun.tidebuy:35357
memcached_servers = controller.yun.tidebuy:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = glance
password = $GLANCE_PASS

[paste_deploy]
flavor = keystone
#" > /etc/glance/glance-registry.conf

/bin/sh -c "glance-manage db_sync" glance
mysql -h controller.yun.tidebuy -u glance -p$GLANCE_DBPASS -e "use glance;show tables;"

echo '启动 glance'
systemctl enable openstack-glance-api.service openstack-glance-registry.service
systemctl restart openstack-glance-api.service openstack-glance-registry.service

echo '安装 nova 控制节点'
yum install openstack-nova-api openstack-nova-conductor \
openstack-nova-console openstack-nova-novncproxy \
openstack-nova-scheduler openstack-nova-placement-api -y

echo '设置 nova 控制节点相关配置'
cp /etc/nova/nova.conf{,.$(date +%s).bak}
cp /etc/httpd/conf.d/00-nova-placement-api.conf{,.$(date +%s).bak}

echo "#
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:$RABBIT_PASS@controller.yun.tidebuy
my_ip = "$MY_IP"
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api_database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@controller.yun.tidebuy/nova_api

[database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@controller.yun.tidebuy/nova

[api]
auth_strategy = keystone

[keystone_authtoken]
auth_uri = http://controller.yun.tidebuy:5000
auth_url = http://controller.yun.tidebuy:35357
memcached_servers = controller.yun.tidebuy:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = $NOVA_PASS

[vnc]
enabled = true
vncserver_listen = "$MY_IP"
vncserver_proxyclient_address = "$MY_IP"

[glance]
api_servers = http://controller.yun.tidebuy:9292
[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
os_region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller.yun.tidebuy:35357/v3
username = placement
password = $PLACEMENT_PASS

[scheduler]
discover_hosts_in_cells_interval = 300
#">/etc/nova/nova.conf

echo "

#Placement API
<Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
</Directory>
">>/etc/httpd/conf.d/00-nova-placement-api.conf

systemctl restart httpd

echo '填充 nova 相关数据库'
/bin/sh -c "nova-manage api_db sync" nova
/bin/sh -c "nova-manage cell_v2 map_cell0" nova
/bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
/bin/sh -c "nova-manage db sync" nova

echo '检查 nova 相关数据库'
nova-manage cell_v2 list_cells
mysql -h controller.yun.tidebuy -u nova -p$NOVA_DBPASS -e "use nova_api;show tables;"
mysql -h controller.yun.tidebuy -u nova -p$NOVA_DBPASS -e "use nova;show tables;" 
mysql -h controller.yun.tidebuy -u nova -p$NOVA_DBPASS -e "use nova_cell0;show tables;"

echo '启动 nova 相关服务'
systemctl enable openstack-nova-api.service \
openstack-nova-consoleauth.service openstack-nova-scheduler.service \
openstack-nova-conductor.service openstack-nova-novncproxy.service

systemctl restart openstack-nova-api.service \
openstack-nova-consoleauth.service openstack-nova-scheduler.service \
openstack-nova-conductor.service openstack-nova-novncproxy.service

echo '安装 neutron'
yum install -y openstack-neutron openstack-neutron-ml2 \
 openstack-neutron-linuxbridge python-neutronclient ebtables ipset

echo '设置 neutron 控制节点相关配置'
cp /etc/neutron/neutron.conf{,.$(date +%s).bak}
cp /etc/neutron/plugins/ml2/ml2_conf.ini{,.$(date +%s).bak}
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini{,.$(date +%s).bak}
cp /etc/neutron/dhcp_agent.ini{,.$(date +%s).bak}
cp /etc/neutron/metadata_agent.ini{,.$(date +%s).bak}
cp /etc/neutron/l3_agent.ini{,.$(date +%s).bak}

echo "
#
[neutron]
url = http://controller.yun.tidebuy:9696
auth_url = http://controller.yun.tidebuy:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASS
service_metadata_proxy = true
metadata_proxy_shared_secret = metadata
#">>/etc/nova/nova.conf

echo '
[DEFAULT]
nova_metadata_ip = controller.yun.tidebuy
metadata_proxy_shared_secret = metadata
#'>/etc/neutron/metadata_agent.ini

echo '#
[ml2]
tenant_network_types = 
type_drivers = vlan,flat
mechanism_drivers = linuxbridge
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[securitygroup]
enable_ipset = True
#'>/etc/neutron/plugins/ml2/ml2_conf.ini

echo '#
[linux_bridge]
physical_interface_mappings = provider:'$NET_NAME'
[vxlan]
enable_vxlan = false

[agent]
prevent_arp_spoofing = True
[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
enable_security_group = True
#'>/etc/neutron/plugins/ml2/linuxbridge_agent.ini

echo '#
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
#'>/etc/neutron/dhcp_agent.ini

echo "
[DEFAULT]
core_plugin = ml2
service_plugins = 
allow_overlapping_ips = true
transport_url = rabbit://openstack:$RABBIT_PASS@controller.yun.tidebuy
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[keystone_authtoken]
auth_uri = http://controller.yun.tidebuy:5000
auth_url = http://controller.yun.tidebuy:35357
memcached_servers = controller.yun.tidebuy:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_PASS

[nova]
auth_url = http://controller.yun.tidebuy:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = RegionOne
project_name = service
username = nova
password = $NOVA_PASS

[database]
connection = mysql://neutron:$NEUTRON_DBPASS@controller.yun.tidebuy:3306/neutron

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp 
#">/etc/neutron/neutron.conf

echo '
[DEFAULT]
interface_driver = linuxbridge
#'>/etc/neutron/l3_agent.ini

echo '填充 neutron 相关数据库'
/bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

echo '检查 neutron 相关数据库'
mysql -h controller.yun.tidebuy -u neutron -p$NEUTRON_DBPASS -e "use neutron;show tables;" 

echo '启动 neutron 相关服务'
systemctl restart openstack-nova-api.service
systemctl enable neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
systemctl restart neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
 
echo "查看网络列表"
openstack network agent list  

echo "安装 Dashboard web管理界面"
yum install openstack-dashboard -y

echo '设置 Dashboard web 相关配置'
cp /etc/openstack-dashboard/local_settings{,.$(date +%s).bak}

DASHBOARD_SETTINGS=/etc/openstack-dashboard/local_settings
sed -i 's#_member_#user#g' $DASHBOARD_SETTINGS
sed -i 's#OPENSTACK_HOST = "127.0.0.1"#OPENSTACK_HOST = "controller.yun.tidebuy"#' $DASHBOARD_SETTINGS
##允许所有主机访问#
sed -i "/ALLOWED_HOSTS/cALLOWED_HOSTS = ['*', ]" $DASHBOARD_SETTINGS
#去掉memcached注释#
sed -in '153,158s/#//' $DASHBOARD_SETTINGS 
sed -in '160,164s/.*/#&/' $DASHBOARD_SETTINGS
sed -i 's#UTC#Asia/Shanghai#g' $DASHBOARD_SETTINGS
sed -i 's#%s:5000/v2.0#%s:5000/v3#' $DASHBOARD_SETTINGS
sed -i '/ULTIDOMAIN_SUPPORT/cOPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True' $DASHBOARD_SETTINGS
sed -i "s@^#OPENSTACK_KEYSTONE_DEFAULT@OPENSTACK_KEYSTONE_DEFAULT@" $DASHBOARD_SETTINGS
echo '
#set
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 2,
}
#'>>$DASHBOARD_SETTINGS

echo '重启 httpd web服务'
systemctl restart httpd