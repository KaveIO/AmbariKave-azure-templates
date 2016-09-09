#!/bin/bash
#This is to be executed on the cluster node designated for ambari

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

VERSION=${1:-2.0-Beta}
WORKING_DIR=${2:-/root/kavesetup}

function download_kave {
    local artifact="$WORKING_DIR/$VERSION.zip"
    wget --tries=30 --read-timeout=60 "https://github.com/KaveIO/AmbariKave/archive/$VERSION.zip" -O "$artifact"
    unzip -o "$artifact" -d "$WORKING_DIR"
}

function patch_kave {
    # The support for centos 7 and the fix for long domain names mess each other up. Get rid of the guard in the params file to work it with 
    # the longnames check avoided.... 
    cp "$WORKING_DIR"/contents/automation/patch/freeipa_params.py "$WORKING_DIR"/AmbariKave-$VERSION/src/KAVE/services/FREEIPA/package/scripts/params.py
}

download_kave

#To avoid conflicts with what the Kave installer installs
yum remove -y epel-release
yum remove -y sshpass pdsh

service iptables stop
chkconfig iptables off
cd "$WORKING_DIR/AmbariKave-$VERSION"
dev/install.sh
patch_kave
dev/patch.sh
ambari-server start
