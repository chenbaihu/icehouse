#!/bin/bash

set -e
set -o xtrace

#---------------------------------------------
# Set up Env.
#---------------------------------------------

TOPDIR=$(cd $(dirname "$0") && pwd)
source $TOPDIR/localrc
source $TOPDIR/tools/function
TEMP=`mktemp`; rm -rfv $TEMP >/dev/null; mkdir -p $TEMP;


#---------------------------------------------
# Get Password
#---------------------------------------------

set_password MYSQL_ROOT_PASSWORD


#---------------------------------------------
# Install mysql by apt-get
#---------------------------------------------

apt_get openssh-server mysql-server

#---------------------------------------------
# Set root's password
#---------------------------------------------

if [[ `cat /etc/mysql/my.cnf | grep "0.0.0.0" | wc -l` -eq 0 ]]; then
    mysqladmin -uroot password $MYSQL_ROOT_PASSWORD
fi
sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
service mysql restart


#---------------------------------------------
# Give root's right
#---------------------------------------------
mysql_local_root_cmd "use mysql; delete from user where user=''; flush privileges;"
mysql_local_root_cmd "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' identified by '$MYSQL_ROOT_PASSWORD'; FLUSH PRIVILEGES;"
mysql_local_root_cmd "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' identified by '$MYSQL_ROOT_PASSWORD'  WITH GRANT OPTION; FLUSH PRIVILEGES;"
mysql_local_root_cmd "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' identified by '$MYSQL_ROOT_PASSWORD'; FLUSH PRIVILEGES;"
mysql_local_root_cmd "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' identified by '$MYSQL_ROOT_PASSWORD'  WITH GRANT OPTION; FLUSH PRIVILEGES;"
mysql_local_root_cmd "flush privileges;"
service mysql restart

set +o xtrace
