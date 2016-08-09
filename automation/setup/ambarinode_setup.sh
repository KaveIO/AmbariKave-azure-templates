#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

REPOSITORY=$1
USER=$2
PASS=$3
HOSTS="localhost $4"
VERSION=$5
KAVE_BLUEPRINT_URL=$6
KAVE_CLUSTER_URL=$7
DESTDIR=${8:-contents}
SWAP_SIZE=${9:-10g}
WORKING_DIR=${10:-/root/kavesetup}
CLUSTER_NAME=${11:-cluster}

CURL_AUTH_COMMAND='curl --netrc -H X-Requested-By:KoASetup -X'
CLUSTERS_URL="http://localhost:8080/api/v1/clusters"

function anynode_setup {
    chmod +x "$DIR/anynode_setup.sh"
    
    "$DIR/anynode_setup.sh" "$REPOSITORY" "$USER" "$PASS" "$DESTDIR" "$SWAP_SIZE" "$WORKING_DIR"
}

function csv_hosts {
    CSV_HOSTS=$(echo "$HOSTS" | tr ' ' ,)
}

function download_blueprint {
    local extension=.json.template
    local blueprint_filename=blueprint$extension
    local cluster_filename="$CLUSTER_NAME"$extension
    
    wget --tries=10 --read-timeout=60 -O "$WORKING_DIR/$blueprint_filename" "$KAVE_BLUEPRINT_URL"

    wget --tries=10 --read-timeout=60 -O "$WORKING_DIR/$cluster_filename" "$KAVE_CLUSTER_URL"

    KAVE_BLUEPRINT=$(readlink -e "$WORKING_DIR/$blueprint_filename")

    KAVE_CLUSTER=$(readlink -e "$WORKING_DIR/$cluster_filename")
}

function define_bindir {
    BIN_DIR=$WORKING_DIR/$DESTDIR/automation/setup/bin
}

function distribute_keys {
    $BIN_DIR/distribute_keys.sh "$USER" "$PASS" "$HOSTS"
}

function customize_hosts {
    $BIN_DIR/create_hostsfile.sh "$WORKING_DIR" "$HOSTS"

    pdcp -w "$CSV_HOSTS" "$WORKING_DIR/hosts" /etc/hosts
}

function localize_cluster_file {
    $BIN_DIR/localize_cluster_file.sh "$KAVE_CLUSTER"
}

function initialize_blueprint {
    sed -r s/"<KAVE_ADMIN>"/"$USER"/g "$KAVE_BLUEPRINT" > "${KAVE_BLUEPRINT%.*}"
}

function kave_install {
    $BIN_DIR/kave_install.sh "$VERSION" "$WORKING_DIR"
}

function patch_ipa {
    #Install FreeIPA server and patch it; as this is a regular yum install Ambari will try to reinstall it but it will not be overwritten of course
    yum install -y ipa-server
    
    #Why this? In different parts of the code the common name (CN) is build concatenating the DNS domain name and the string "Certificate Authority", and in our case due to Azure long DNSDN the field ends up to be longer than 64 chars which is the RFC-defined standard maximum. This suffix is added as a naming convention, so we cannot just drop it, rather amend it.

    grep -IlR "Certificate Authority" /usr/lib/python2.6/site-packages/ipa* | xargs sed -i 's/Certificate Authority/CA/g'
    #To be fixed in FreeIPA (ideally, but it won't be the case)
    #To be fixed in KAVE (installation will refuse to continue if the total string "FQDN + "Certificate Authority" is longer than 64 OR it gives the option to apply this patch
}

function wait_for_ambari {
    cp "$BIN_DIR/../.netrc" ~
    until curl --netrc -fs http://localhost:8080/api/v1/clusters; do
	sleep 60
	echo "Waiting until ambari server is up and running..."
    done
}

blueprint_trials=5

function blueprint_deploy {
    #REST connection in deploy_from_blueprint.py can fail, so keep trying till success is reached
    local command="$BIN_DIR/blueprint_deploy.sh $VERSION ${KAVE_BLUEPRINT%.*} ${KAVE_CLUSTER%.*} $WORKING_DIR"
    # do not try more than 10 times before trying to do something else
    local count=3 
    command="echo 'dummy command...';false"
    while $command && test $count -ne 0; do 
	((count--))
	echo "Blueprint installation failed, retrying..."
	echo "DEBUG: count="$count
	sleep 30
    done
    # try to re-install ambari in case deployment was not successful
    if [ $count -eq 0 ] && [ $blueprint_trials -ne 0 ]; then
	((blueprint_trials--))
	echo "Blueprint deployment unsucessful. Reinstalling ambari server and retrying the deployment..."
	echo $blueprint_trials" deployment trials remaining"
	pdsh -w "$CSV_HOSTS" "service ambari-agent stop; yum -y erase ambari-agent"
	cd "$WORKING_DIR/AmbariKave-$VERSION"
	service ambari-server stop
	su -c "dev/clean.sh<<EOF
> y
> EOF"
	kave_install
	blueprint_deploy
    else
	echo "deployment successful"
	return 0
    fi
}

function wait_on_deploy() {
    until wait_on_deploy_impl; do
	echo "Ambari tasks taking too long, restarting the Ambari cluster..."
	service ambari-server restart
	sleep 120
	pdsh -w "$CSV_HOSTS" "service ambari-agent restart"
	sleep 120
	done
}

wait_on_deploy_impl() {
    #We start only after the regular blueprint deployment is done, and we are done when there are no running or scheduled requests.
    sleep 300
    local command="$CURL_AUTH_COMMAND"
    local count=150
    while ($command GET "$CLUSTERS_URL/$CLUSTER_NAME/requests?fields=Requests" 2> /dev/null | egrep "IN_PROGRESS|PENDING|QUEUED") && test $count -ne 0; do
	((count--))
	sleep 15
	echo "Waiting for background tasks in Ambari to complete..."
    done
    test $count -ne 0
}


function enable_kaveadmin {
    cat /root/admin-password | kinit admin
    su -c "
        ipa user-mod $USER --password<<EOF
        $PASS
        $PASS
EOF"
    # let the changes propagate through the cluster
    sleep 120
}

anynode_setup

csv_hosts

download_blueprint

define_bindir

distribute_keys

customize_hosts

localize_cluster_file

initialize_blueprint

kave_install

patch_ipa

wait_for_ambari

blueprint_deploy

#wait_on_deploy

#enable_kaveadmin
