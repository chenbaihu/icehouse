#!/bin/bash


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

function init_ssh() {
    host_list=`get_host_list`
    for node in $host_list; do
        ssh $node "echo ok"
        host_name=`cat /etc/hosts | grep $node | awk '{print $2}'`
        ssh $host_name "echo ok"
    done
}

function main() {
    init_ssh
}

main

