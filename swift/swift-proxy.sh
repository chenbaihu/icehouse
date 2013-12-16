#!/bin/bash

set -e
set -o xtrace

#---------------------------------------------
# Set up ENV.
#---------------------------------------------

TOPDIR=$(cd $(dirname "$0") && pwd)
TEMP=`mktemp`;
rm -rfv $TEMP >/dev/null;
mkdir -p $TEMP;
source $TOPDIR/localrc
source $TOPDIR/tools/function
DEST=/opt/stack/
mkdir -p $DEST

if [[ ! -e $DEST/.swift ]]; then
    old_path=`pwd`
    cd $DEST
    virtualenv .swift
    cd .keystone/bin/
    source activate
    cd $old_path
else
    source $DEST/.swift/bin/activate
fi


###########################################################
#
#  Your Configurations.
#
###########################################################

BASE_SQL_CONN=mysql://$MYSQL_NOVA_USER:$MYSQL_NOVA_PASSWORD@$MYSQL_HOST

unset OS_USERNAME
unset OS_AUTH_KEY
unset OS_AUTH_TENANT
unset OS_STRATEGY
unset OS_AUTH_STRATEGY
unset OS_AUTH_URL
unset SERVICE_TOKEN
unset SERVICE_ENDPOINT
unset http_proxy
unset https_proxy
unset ftp_proxy

KEYSTONE_AUTH_HOST=$KEYSTONE_HOST
KEYSTONE_AUTH_PORT=35357
KEYSTONE_AUTH_PROTOCOL=http
KEYSTONE_SERVICE_HOST=$KEYSTONE_HOST
KEYSTONE_SERVICE_PORT=5000
KEYSTONE_SERVICE_PROTOCOL=http
SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0
KEYSTONE_PROTOCOL=http

#---------------------------------------------------
# Clear Front installation
#---------------------------------------------------

DEBIAN_FRONTEND=noninteractive \
apt-get --option \
"Dpkg::Options::=--force-confold" --assume-yes \
install -y --force-yes mysql-client openssh-server build-essential git \
curl gcc git git-core libxml2-dev libxslt-dev \
memcached openssl expect mysql-client unzip \
memcached python-dev python-setuptools python-pip \
sqlite3 xfsprogs libmysqld-dev


[[ -e /usr/include/libxml ]] && rm -rf /usr/include/libxml
ln -s /usr/include/libxml2/libxml /usr/include/libxml


#---------------------------------------------------
# Clear old installation.
#---------------------------------------------------

nkill swift-proxy-server
[[ -d /etc/swift ]] && rm -rf /etc/swift/*
[[ -d $DEST/swift ]] && cp -rf $TOPDIR/source/swift/etc/* $DEST/swift/etc/
mysql_cmd "DROP DATABASE IF EXISTS swift;"


#---------------------------------------------------
# Copy source code to DEST Dir
#---------------------------------------------------

install_keystone
install_swift

#---------------------------------------------------
# Create User in Swift
#---------------------------------------------------

export SERVICE_TOKEN=$ADMIN_TOKEN
export SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0

get_tenant SERVICE_TENANT service
get_role ADMIN_ROLE admin


if [[ `keystone user-list | grep swift | wc -l` -eq 0 ]]; then
SWIFT_USER=$(get_id keystone user-create \
    --name=swift \
    --pass="$KEYSTONE_SWIFT_SERVICE_PASSWORD" \
    --tenant_id $SERVICE_TENANT \
    --email=swift@example.com)
keystone user-role-add \
    --tenant_id $SERVICE_TENANT \
    --user_id $SWIFT_USER \
    --role_id $ADMIN_ROLE
SWIFT_SERVICE=$(get_id keystone service-create \
    --name=swift \
    --type="object-store" \
    --description="Swift Service")
keystone endpoint-create \
    --region RegionOne \
    --service_id $SWIFT_SERVICE \
    --publicurl "http://$SWIFT_HOST:8080/v1/AUTH_\$(tenant_id)s" \
    --adminurl "http://$SWIFT_HOST:8080/v1" \
    --internalurl "http://$SWIFT_HOST:8080/v1/AUTH_\$(tenant_id)s"
fi

unset SERVICE_TOKEN
unset SERVICE_ENDPOINT


#---------------------------------------------------
# Create glance user in Linux-System
#---------------------------------------------------



if [[ `cat /etc/passwd | grep swift | wc -l` -eq 0 ]] ; then
    groupadd swift
    useradd -g swift swift
fi


#---------------------------------------------------
# Swift Configurations
#---------------------------------------------------

[[ -d /etc/swift ]] && rm -rf /etc/swift
mkdir -p /etc/swift
cat >/etc/swift/swift.conf <<EOF
[swift-hash]
swift_hash_path_suffix = `od -t x8 -N 8 -A n </dev/random`
EOF

cd /etc/swift
cat <<"EOF">>auto_ssl.sh
#!/usr/bin/expect -f
spawn openssl req -new -x509 -nodes -out cert.crt -keyout cert.key
expect {
"Country Name*" { send "CN\r"; exp_continue }
"State or Province Name*" { send "Shanghai\r"; exp_continue }
"Locality Name*" {send "Shanghai\r"; exp_continue }
"Organization Name*" { send "internet\r"; exp_continue }
"Organizational Unit Name*" { send "cloud.computing\r"; exp_continue }
"Common Name *" { send "Cloud Computing\r"; exp_continue }
"Email Address*" { send "cloud@openstack.com\r" }
}
expect eof
EOF
chmod a+x auto_ssl.sh
./auto_ssl.sh

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/memcached.conf
service memcached restart

#---------------------------------------------------
# Change configurations for Swift
#---------------------------------------------------

cp -rf $TOPDIR/templates/proxy-server.conf /etc/swift/
file=/etc/swift/proxy-server.conf
mkdir -p /etc/swift/keystone-signing
chmod -R 0700  /etc/swift/keystone-signing


sed -i "s,%KEYSTONE_AUTH_PORT%,$KEYSTONE_AUTH_PORT,g" $file
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" $file
sed -i "s,%KEYSTONE_PROTOCOL%,$KEYSTONE_PROTOCOL,g" $file
sed -i "s,%AUTH_TOKEN%,$ADMIN_TOKEN,g" $file
sed -i "s,%ADMIN_TOKEN%,$ADMIN_TOKEN,g" $file
sed -i "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" $file
sed -i "s,%SERVICE_USER%,swift,g" $file
sed -i "s,%SERVICE_PASSWORD%,$KEYSTONE_SWIFT_SERVICE_PASSWORD,g" $file

#---------------------------------------------------
# Change Rights
#---------------------------------------------------

mkdir -p /etc/swift/keystone-signing
chown -R swift:swift /etc/swift
chown -R swift:swift /etc/swift/keystone-signing
mkdir -p /var/log/swift
chown -R swift:swift /var/log/swift


#---------------------------------------------------
# Build Rings
#---------------------------------------------------


swift-ring-builder object.builder create 18 3 1
swift-ring-builder container.builder create 18 3 1
swift-ring-builder account.builder create 18 3 1

list=${SWIFT_NODE_IP//\{/ }
list=${list//\},/ }
list=${list//\}/ }
zone_iter=1
for n in $list; do
    zone_nodes=${n//,/ }
    for node in $zone_nodes; do
        swift-ring-builder object.builder add z${zone_iter}-${node}:6010/sdb1 100
        swift-ring-builder container.builder add z${zone_iter}-${node}:6011/sdb1 100
        swift-ring-builder account.builder add z${zone_iter}-${node}:6012/sdb1 100
    done
    let "zone_iter = $zone_iter + 1"
done

swift-ring-builder account.builder
swift-ring-builder container.builder
swift-ring-builder object.builder

swift-ring-builder object.builder rebalance
swift-ring-builder container.builder rebalance
swift-ring-builder account.builder rebalance


#---------------------------------------------------
# Create Start up Script in /etc/init.d/
# $ service swift-proxy {start|stop|status|test}
#---------------------------------------------------

mkdir -p /var/log/swift
chown -R swift /var/log/swift

SWIFT_DIR=$DEST/swift
cp -rf $TOPDIR/tools/swift-proxy /etc/init.d/
file=/etc/init.d/swift-proxy
logfile=/var/log/swift/swift.log
sed -i "s,%KEYSTONE_SWIFT_SERVICE_PASSWORD%,$KEYSTONE_SWIFT_SERVICE_PASSWORD,g" $file
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" $file
sed -i "s,%logfile%,$logfile,g" $file
sed -i "s,%SWIFT_DIR%,$SWIFT_DIR,g" $file
sed -i "s,%DEST%,$DEST,g" $file
sed -i "s,%logfile%,$logfile,g" $file

#---------------------------------------------------
# Create swiftrc file
#---------------------------------------------------

cp -rf $TOPDIR/tools/swiftrc /root/
file=/root/swiftrc
sed -i "s,%KEYSTONE_SWIFT_SERVICE_PASSWORD%,$KEYSTONE_SWIFT_SERVICE_PASSWORD,g" $file
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" $file
rm -rf /tmp/pip*; rm -rf /tmp/tmp*

old_path=`pwd`
cd $DEST/.swift/bin/
deactivate
cd $old_path

set +o xtrace
