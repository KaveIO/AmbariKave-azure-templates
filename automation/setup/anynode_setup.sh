#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

REPOSITORY=$1
USER=$2
PASS=$3
DESTDIR=${4:-contents}
SWAP_SIZE=${5:-10g}
WORKING_DIR=${6:-/root/kavesetup}

function setup_repo {
    rm -rf "$WORKING_DIR"
    
    mkdir -p "$WORKING_DIR"
    
    wget --tries=10 --read-timeout=60 -O "$WORKING_DIR/scripts.zip" "$REPOSITORY"

    unzip -d "$WORKING_DIR/temp" "$WORKING_DIR/scripts.zip" 

    mkdir "$WORKING_DIR/$DESTDIR"

    mv "$WORKING_DIR"/temp/*/* "$WORKING_DIR/$DESTDIR"

    rm -rf "$WORKING_DIR"/temp "$WORKING_DIR/scripts.zip"

    AUTOMATION_DIR="$WORKING_DIR/$DESTDIR/automation"
    
    chmod -R +x "$AUTOMATION_DIR/setup"
}

function patch_yum {
    amend_yum_conf
}

amend_yum_conf() {
    #Not sure why is this but yum tries to use v6 pretty randomly - once I failed possibly because of this, let's just force v4. Also, let's just try forever to install a package - if an install
    #does not happen we are in trouble anyway.
    echo "ip_resolve=4" >> /etc/yum.conf
    echo "retries=0" >> /etc/yum.conf
}

function install_packages {
    
    # centos 7 fix. epel is installed differently
    # yum install -y epel-release
    rpm -iUvh http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-8.noarch.rpm

    yum clean all
    
    yum install -y sshpass pdsh

    yum install -y rpcbind

    yum install -y ipa-server ipa-client
}

function change_rootpass {
    echo root:$PASS | chpasswd
}

function disable_iptables {
    #The deploy_from_blueprint KAVE script performs a number of commands on the cluster hosts. Among these, it reads like iptables is stopped, but not permanently. It must be off as otherwise, at least a priori, the FreeIPA clients cannot talk to eachother. We want these changes to be permanent in the (remote) case that the system goes down or is rebooted - otherwise KAVE will stop working afterwards.
    #To be fixed in KAVE
    service iptables stop
    chkconfig iptables off
}

function disable_selinux {
    #Same story as iptables, SELinux must be permanently off but it is only temporary disabled in the blueprint deployment script.
    #To be fixed in KAVE
    echo 0 >/selinux/enforce
    sed -i s/SELINUX=enforcing/SELINUX=disabled/g /etc/selinux/config
}

setup_repo

patch_yum

install_packages

change_rootpass

disable_iptables

disable_selinux
