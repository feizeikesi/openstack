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
