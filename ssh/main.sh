#!/bin/bash
TOPDIR=$(cd $(dirname "$0") && pwd)
sed -i '/^ *$/d' $TOPDIR/localrc

function _gen_template() {
cat <<"EOF" > /tmp/exp.sh
#!/usr/bin/expect -f
spawn %CMD%
expect {
"Enter file in which to save the key (/root/.ssh/id_rsa):" { send "\r"; exp_continue }
"Enter passphrase (empty for no passphrase):" { send "\r"; exp_continue }
"Enter same passphrase again:" { send "\r"; exp_continue }
"continue connecting (yes/no)?" { send "yes\r"; exp_continue }
"s password:" { send "%ROOT_PASSWORD%\r"; exp_continue }
"want to continue connecting (yes/no)?" { send "yes\r"; exp_continue }
"Do you want to continue*" { send "Y\r"; exp_continue }
"Enter file in which to save the key (/root/.ssh/id_rsa):" {send "\r"; exp_continue }
"Enter passphrase (empty for no passphrase):" { send "\r"; exp_continue }
"Enter same passphrase again:" { send "\r"; exp_continue }
}
expect eof
EOF
}


function _auto_cmd() {
    _gen_template
    server_password=$1
    running_cmd=$2
    sed -i "s,%ROOT_PASSWORD%,$server_password,g" /tmp/exp.sh
    sed -i "s,%CMD%,$running_cmd,g" /tmp/exp.sh
    chmod +x /tmp/exp.sh
    /tmp/exp.sh
}

#-------------------------------------------------
# NOTE: The cmd is running on that server.
# Three parameters:
# $1 : server_ip
# $2 : server_password
# $3 : cmd will running on server_ip
#
# For example:
# ssh server_ip "cmd"
# Usage: run_remote_cmd server_ip server_password "rm -rf /tmp/.ssh"
#-------------------------------------------------

function run_remote_cmd() {
    CMD="\"$3\""
    server_ip=$1
    server_password=$2
    run_cmd="ssh $server_ip $CMD"
    _auto_cmd $server_password "$run_cmd"
}


#-------------------------------------------------
# NOTE: The cmd is running on that server.
# Three parameters:
# $1 : server_ip
# $2 : server_password
# $3 : cmd will running on server_ip
#
# For example:
# ssh server_ip "cmd"
# Usage: run_remote_script server server_password /tmp/temp.sh
#-------------------------------------------------

function _copy_and_run_script() {
    server_ip=$1
    server_password=$2
    script_path=$3
    cmd="scp $script_path $server_ip:$script_path"
    _auto_cmd $server_password "$cmd"

    cmd="chmod +x $script_path"
    run_remote_cmd $server_ip $server_password "$cmd"

    cmd="$script_path"
    run_remote_cmd $server_ip $server_password "$cmd"
}


function _copy_remote_key() {
    server_ip=$1
    server_password=$2
    this_host=`hostname`
    script_file=/tmp/tmp.sh
cat <<"EOF" > $script_file
    rm -rf /root/.ssh
    ssh-keygen
EOF
    sed -i "s,%this_host%,$this_host,g" $script_file
    _copy_and_run_script $server_ip $server_password $script_file
    _auto_cmd $server_password "scp -pr /root/.ssh/id_rsa.pub $this_host:/tmp/$server_ip"
}

function configure_host_name() {
    hnlist=/tmp/host_name_list
    rm -rf $hnlist
    cat $TOPDIR/localrc |grep -v "^$" |  while read line; do
        file=`mktemp`
        remote_host_ip=`echo $line | awk '{print $1}'`
        remote_password=`echo $line | awk '{print $2}'`
        run_remote_cmd $remote_host_ip $remote_password "hostname > $file"
        _auto_cmd $remote_password "scp $remote_host_ip:$file $file"
        sed -i "/^ *$/d" $file
        host_name=`cat $file`
        echo "$remote_host_ip $host_name" >> $hnlist
        run_remote_cmd $remote_host_ip $remote_password "rm -rf $file"
        rm -rf $file
    done

    cat $TOPDIR/localrc |grep -v "^$" |  while read line; do
        remote_host_ip=`echo $line | awk '{print $1}'`
        remote_password=`echo $line | awk '{print $2}'`
        run_remote_cmd $remote_host_ip $remote_password "sed -i '/$remote_host_ip/d'"
    done
 
    cat $TOPDIR/localrc |grep -v "^$" |  while read line; do
        remote_host_ip=`echo $line | awk '{print $1}'`
        remote_password=`echo $line | awk '{print $2}'`
        _auto_cmd $remote_password "scp $hnlist $remote_host_ip:/tmp/"
        run_remote_cmd $remote_host_ip $remote_password "cat $hnlist >> /etc/hots"
    done
}

function init_ssh() {
    hnlist=/tmp/host_name_list
    cp -rf $TOPDIR/localrc /tmp/

    cat <<"EOF" > /tmp/init_ssh.sh
        cat /tmp/localrc |grep -v "^$" |  while read line; do
            x_ip=`echo $line | awk '{print $1}'`
            x_pd=`echo $line | awk '{print $2}'`
            x_hn=`cat /tmp/host_name_list | grep $x_ip | awk '{print $2}'`

            cp /tmp/template.sh /tmp/run.sh
            sed -i "s,%CMD%,ssh $x_ip pwd,g" /tmp/run.sh
            sed -i "s,%ROOT_PASSWORD%,$x_pd,g" /tmp/run.sh
            chmod +x /tmp/run.sh
            /tmp/run.sh

            cp /tmp/template.sh /tmp/run.sh
            sed -i "s,%CMD%,ssh $x_hn pwd,g" /tmp/run.sh
            sed -i "s,%ROOT_PASSWORD%,$x_pd,g" /tmp/run.sh
            chmod +x /tmp/run.sh
            /tmp/run.sh
        done
EOF
    _gen_template
    cp -rf /tmp/exp.sh /tmp/template.sh
    cat $TOPDIR/localrc |grep -v "^$" |  while read line; do
        remote_host_ip=`echo $line | awk '{print $1}'`
        remote_password=`echo $line | awk '{print $2}'`
        _auto_cmd $remote_password "scp -pr /tmp/localrc $remote_host_ip:/tmp/"
        _auto_cmd $remote_password "scp -pr /tmp/init_ssh.sh $remote_host_ip:/tmp/"
        _auto_cmd $remote_password "scp -pr /tmp/template.sh $remote_host_ip:/tmp/"

        run_remote_cmd $remote_host_ip $remote_password "chmod +x /tmp/init_ssh.sh"
        run_remote_cmd $remote_host_ip $remote_password "/tmp/init_ssh.sh"
        #run_remote_cmd $remote_host_ip $remote_password "rm -rf /tmp/localrc"
        #run_remote_cmd $remote_host_ip $remote_password "rm -rf /tmp/init_ssh.sh"
        #run_remote_cmd $remote_host_ip $remote_password "rm -rf /tmp/exp.sh"
    done
 
}

function main() {
    cat $TOPDIR/localrc |grep -v "^$" |  while read line; do
        remote_host_ip=`echo $line | awk '{print $1}'`
        remote_password=`echo $line | awk '{print $2}'`
        _copy_remote_key $remote_host_ip $remote_password
    done

    rm -rf /tmp/authorized_keys
    cat $TOPDIR/localrc |grep -v "^$" |  while read line; do
        remote_host_ip=`echo $line | awk '{print $1}'`
        remote_password=`echo $line | awk '{print $2}'`
        cat /tmp/$remote_host_ip >> /tmp/authorized_keys
    done

    cat $TOPDIR/localrc |grep -v "^$" |  while read line; do
        remote_host_ip=`echo $line | awk '{print $1}'`
        remote_password=`echo $line | awk '{print $2}'`
        _auto_cmd $remote_password "scp /tmp/authorized_keys $remote_host_ip:~/.ssh/"
    done

    configure_host_name
    init_ssh
}

main
