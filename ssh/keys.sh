#!/bin/bash

set -o xtrace

TOPDIR=$(cd $(dirname "$0") && pwd)
source $TOPDIR/localrc

function get_host_list() {
    list=${NODE_IP//\{/ }
    list=${list//\},/ }
    list=${list//\}/ }
    ret=""
    for n in $list; do
        zone_nodes=${n//,/ }
        for node in $zone_nodes; do
            merge=`echo $ret $node`
            ret=$merge
        done
    done
    echo $ret
}

function get_host_name() {
    hn=`ssh $1 "hostname"`
    echo $hn
}

function change_hosts_file() {
    host_list=`get_host_list`
    for node in $host_list; do
        host_name=`get_host_name $node`
        ssh $node "sed -i \"s,127.0.1.1.*,127.0.1.1        $host_name,g\" /etc/hosts"
        for host in $host_list; do
            hnn=`get_host_name $host`
            ssh $node "sed -i \"/$host/d\" /etc/hosts"
            ssh $node "echo \"$host $hnn\" >> /etc/hosts"
        done
    done
}

function configure_ssh() {
    host_list=`get_host_list`
    for node in $host_list; do
        hn=`get_host_name $node`
        if [[ $hn != `hostname` ]]; then
            ssh $node "mkdir -p $TOPDIR"
            scp -pr $TOPDIR/* $node:$TOPDIR/
            ssh $node "[[ -e /root/.ssh ]] && rm -rf /root/.ssh"
            ssh $node "$TOPDIR/ssh.sh"
            scp $node:/root/.ssh/id_rsa.pub /tmp/$node
        fi
    done

    for node in $host_list; do
        cat /tmp/$node >> /tmp/authorized_keys
    done

    for node in $host_list; do
        scp /tmp/authorized_keys $node:/root/.ssh/
    done
}

function init_ssh() {
    host_list=`get_host_list`
    for node in $host_list; do
        ssh $node "$TOPDIR/init_ssh_exp.sh"
    done
}

function main() {
    #change_hosts_file
    configure_ssh
    init_ssh
}

main

set +o xtrace
