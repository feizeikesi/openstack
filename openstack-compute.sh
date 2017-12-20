
MY_IP=10.10.0.2
VNC_PROXY=192.168.0.156 #VNC代理外网IP地址
VDIR=/data/nova #nova 根目录
VHD=$VDIR/instances
NET_NAME=em2

yum install -y openstack-nova-compute python-openstackclient openstack-selinux

mkdir -p $VDIR
mkdir -p $VHD
chown -R nova:nova $VDIR
echo "Nova实例路径 $VHD"

#使用QEMU或KVM ,KVM硬件加速需要硬件支持
[[ `egrep -c '(vmx|svm)' /proc/cpuinfo` = 0 ]] && { KVM=qemu; } || { KVM=kvm; }
echo "使用 $KVM"

cp /etc/nova/nova.conf{,.$(date +%s).bak}

echo '#
[DEFAULT]
#instances_path='$VHD' #最好不修改,centos引发权限问题
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:'$RABBIT_PASS'@controller.yun.tidebuy
my_ip = '$MY_IP'
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api_database]
connection = mysql+pymysql://nova:'$NOVA_DBPASS'@controller.yun.tidebuy/nova_api
[database]
connection = mysql+pymysql://nova:'$NOVA_DBPASS'@controller.yun.tidebuy/nova

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
password = '$NOVA_PASS'

[vnc]
enabled = true
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = $my_ip
novncproxy_base_url = http://'$VNC_PROXY':6080/vnc_auto.html

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
password = '$PLACEMENT_PASS'

[libvirt]
virt_type = '$KVM'
#'>/etc/nova/nova.conf

systemctl enable libvirtd.service openstack-nova-compute.service
systemctl restart libvirtd.service openstack-nova-compute.service

yum install -y openstack-neutron-linuxbridge ebtables ipset

cp /etc/neutron/neutron.conf{,.$(date +%s).bak}
cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini{,.$(date +%s).bak}

echo '#
[DEFAULT]
auth_strategy = keystone
transport_url = rabbit://openstack:'$RABBIT_PASS'@controller.yun.tidebuy

[keystone_authtoken]
auth_uri = http://controller.yun.tidebuy:5000
auth_url = http://controller.yun.tidebuy:35357
memcached_servers = controller.yun.tidebuy:11211
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = '$NEUTRON_PASS'

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
#'>/etc/neutron/neutron.conf

echo '
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
password = '$NEUTRON_PASS'
#'>>/etc/nova/nova.conf


echo '
[linux_bridge]
physical_interface_mappings = provider:'$NET_NAME'

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

[vxlan]
enable_vxlan = false
#'>/etc/neutron/plugins/ml2/linuxbridge_agent.ini

#重启相关服务
systemctl restart openstack-nova-compute.service
#启动neutron
systemctl enable neutron-linuxbridge-agent.service
systemctl restart neutron-linuxbridge-agent.service
