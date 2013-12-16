#!/bin/bash

set -o xtrace

#---------------------------------------------------
# Create ch.sh
#---------------------------------------------------

cat <<"EOF"> /tmp/ch.sh
#!/bin/bash
rm -rf *type
for n in `ls | grep -E "(*z$|*zip$|*bz2$)"`
do
    mv $n ${n##*2F}
done
EOF
chmod +x /tmp/ch.sh


#---------------------------------------------------
# Prepare ENV
#---------------------------------------------------

TOPDIR=$(cd $(dirname "$0") && pwd)
source $TOPDIR/localrc
TEMP=`mktemp`; rm -rfv $TEMP >/dev/null;mkdir -p $TEMP;

#---------------------------------------------------
# Install apt packages
#---------------------------------------------------

apt-get install -y --force-yes openssh-server build-essential git \
python-dev python-setuptools python-pip libxml2-dev \
libxslt1.1 libxslt1-dev libgnutls-dev libnl-3-dev \
python-virtualenv libnspr4-dev libnspr4 pkg-config \
apache2 unzip


[[ -e /usr/include/libxml ]] && rm -rf /usr/include/libxml
ln -s /usr/include/libxml2/libxml /usr/include/libxml
[[ -e /usr/include/netlink ]] && rm -rf /usr/include/netlink
ln -s /usr/include/libnl3/netlink /usr/include/netlink

#---------------------------------------------------
# Collect pip packages
#---------------------------------------------------

mkdir -p /tmp/pip

files=${FILE_LIST//,/ }

for file in $files; do
    mkdir -p /tmp/pip
    cd $TEMP; virtualenv test; source test/bin/activate

    pip install \
        -r $TOPDIR/$file \
        --download-cache=/tmp
    cd /tmp/; ./ch.sh
    mv /tmp/*z /tmp/pip/
    mv /tmp/*zip /tmp/pip/
    mv /tmp/*bz2 /tmp/pip/

    deactivate
    rm -rf $TEMP/test
done

for file in $files; do
    cat $file | grep -v "^#" | while read line; do
        mkdir -p /tmp/pip
        cd $TEMP; virtualenv test; source test/bin/activate

        echo "Install $line"

        pip install \
            -r ${line%\#*} \
            --download-cache=/tmp
        cd /tmp/; ./ch.sh
        mv /tmp/*z /tmp/pip/
        mv /tmp/*zip /tmp/pip/
        mv /tmp/*bz2 /tmp/pip/

        deactivate
        rm -rf $TEMP/test
    done
done

unset http_proxy
unset https_proxy
unset ftp_proxy

#---------------------------------------------------
# Delete some packages
#---------------------------------------------------


#---------------------------------------------------
# Create pip resources
#---------------------------------------------------

mkdir -p /var/www/pip
cd /tmp/pip

for n in `find . -name "*"`; do
    if [[ ! -d $n ]]; then
        package_name=${n##*/}
        dir_name=${package_name%-*}
        mkdir -p /var/www/pip/$dir_name
        cp -rf $n /var/www/pip/$dir_name

        olddir=`pwd`
        cd /var/www/pip/$dir_name
        TEMP_DIR=`mktemp`; rm -rfv $TEMP_DIR >/dev/null;mkdir -p $TEMP_DIR;
        cp -rf $package_name $TEMP_DIR/
        cd $TEMP_DIR

        if [[ `echo $package_name | grep zip| wc -l` -gt 0 ]]; then
            unzip $package_name
        else

            if [[ `echo $package_name | grep bz2| wc -l` -gt 0 ]]; then
                tar xjf $package_name
            else
                tar zxf $package_name
            fi
        fi

        rm -rf $package_name
        temp_dir_name=`ls`
        cd `ls`;
        if [[ `ls | grep "egg-info"| wc -l` -gt 0 ]]; then
            source /root/proxy
            python setup.py egg_info; python setup.py build
            unset http_proxy; unset https_proxy; unset ftp_proxy
        fi
        cd ..
        if [[ `echo $package_name | grep zip| wc -l` -gt 0 ]]; then
            zip -r $package_name $temp_dir_name
        else
            if [[ `echo $package_name | grep bz2| wc -l` -gt 0 ]]; then
                tar cjf $package_name $temp_dir_name
            else
                tar zcf $package_name $temp_dir_name
            fi
        fi

        rm -rf $temp_dir_name
        cp -rf $package_name /var/www/pip/$dir_name/

        cd $olddir
        rm -rf $TEMP_DIR
    fi
done
chmod -R a+r /var/www

rm -rf /tmp/tmp.*
set +o xtrace
