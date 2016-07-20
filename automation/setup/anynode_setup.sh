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
    
    wget -O "$WORKING_DIR/scripts.zip" "$REPOSITORY"

    unzip -d "$WORKING_DIR/temp" "$WORKING_DIR/scripts.zip" 

    mkdir "$WORKING_DIR/$DESTDIR"

    mv "$WORKING_DIR"/temp/*/* "$WORKING_DIR/$DESTDIR"

    rm -rf "$WORKING_DIR"/temp "$WORKING_DIR/scripts.zip"

    AUTOMATION_DIR="$WORKING_DIR/$DESTDIR/automation"
    
    chmod -R +x "$AUTOMATION_DIR/setup"
}

function patch_yum {
    set_archive_repo
    set_v4_only
}

set_archive_repo() {
    #The 6.5 dirs were wiped out the default yum repo of OpenLogic, therefore we have to use the official repo. So yes 6.5 is still supported as the 6 branch still is, even if the latest-greatest is 6.8.
    local repodir=/etc/yum.repos.d
    rm $repodir/*
    cp "$AUTOMATION_DIR"/patch/CentOS-Official.repo $repodir
}

set_v4_only() {
    #Not sure why is this but yum tries to use v6 pretty randomly. Last time I failed possibly because of this, let's just force v4.
    echo "ip_resolve=4" >> /etc/yum.conf
}

function install_packages {
    yum install -y epel-release

    yum install -y sshpass pdsh

    yum install -y rpcbind
}

function change_name {
    local sname=`hostname -s`
    echo `hostname -d` >> domain.name
    python $AUTOMATION_DIR/setup/bin/rename_me.py $sname "akave.io"
}

function change_rootpass {
    echo root:$PASS | chpasswd
}

function configure_swap {
    local swapfile=/mnt/resource/swap$SWAP_SIZE

    fallocate -l "$SWAP_SIZE" "$swapfile"

    chmod 600 "$swapfile"

    mkswap "$swapfile"

    swapon "$swapfile"

    echo -e "$swapfile\tnone\tswap\tsw\t0\t0" >> /etc/fstab
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

change_name

patch_yum

install_packages

change_rootpass

configure_swap

disable_iptables

disable_selinux


