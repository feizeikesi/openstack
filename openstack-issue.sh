
#删除相关日志
rm -f /var/log/nova/*
rm -f /var/log/neutron/*
rm -f /var/log/glance/*
rm -f /var/log/keystone/*
rm -f /var/log/httpd/*

#过滤错误日志
grep 'ERROR' /var/log/nova/*
grep 'ERROR' /var/log/neutron/*
grep 'ERROR' /var/log/glance/*
grep 'ERROR' /var/log/keystone/*
grep 'ERROR' /var/log/httpd/*

#虚拟机网络正常，网页控制台报错 "错误：无法连接到Neutron"
sed -i "s#'enable_router': True#'enable_router': False#" /etc/openstack-dashboard/local_settings
systemctl restart httpd.service

#中文乱码问题
echo '
import sys
sys.setdefaultencoding('utf-8')
'>/usr/lib/python2.7/site-packages/sitecustomize.py

#创建Provider networks网络
openstack network create --share --provider-physical-network provider \
  --provider-network-type flat provider
openstack subnet create --network provider \
  --allocation-pool start=10.10.1.2,end=10.10.1.253 \
  --dns-nameserver 8.8.4.4 --gateway 10.10.1.1 \
  --subnet-range 10.10.1.0/24 provider