#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

REPOSITORY=$1
USER=$2
PASS=$3
HOSTS="localhost $4"
VERSION=$5
KAVE_BLUEPRINT_URL=$6
KAVE_CLUSTER_URL=$7
DESTDIR=${9:-contents}
SWAP_SIZE=${10:-10g}
WORKING_DIR=${11:-/root/kavesetup}
CLUSTER_NAME=${8:-cluster}
IPA_SERVER_NAME=${12:-ambari}

CURL_AUTH_COMMAND='curl --netrc -H X-Requested-By:KoASetup -X'
CLUSTERS_URL="http://localhost:8080/api/v1/clusters"
COMPONENTS_URL="$CLUSTERS_URL/$CLUSTER_NAME/hosts/<HOST>/host_components"

BLUEPRINT_TRIALS=5
AMBARI_TRIALS=5

REQUEST_NUMBER=1

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
    sed -e s/"<KAVE_ADMIN>"/"$USER"/g -e s/"<KAVE_ADMIN_PASS>"/"$PASS"/g "$KAVE_BLUEPRINT" > "${KAVE_BLUEPRINT%.*}"
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

clean() {
    echo "y" | "$WORKING_DIR/AmbariKave-$VERSION/dev/clean.sh" 
}



function wait_for_ambari {
    cp "$BIN_DIR/../.netrc" ~
    local count=5
    until curl --netrc -fs $CLUSTERS_URL || test $count -eq 0; do
	((count--))
	sleep 60
	echo "Waiting until ambari server is up and running..."
    done
    if [ $count -eq 0 ] && [ $AMBARI_TRIALS -ne 0]; then
	((AMBARI_TRIALS--))
	echo "ambari server is not up and running after 5 minutes waiting: cleaning and reinstalling NOW"
	echo $AMBARI_TRIALS" ambari installation trials remaining."
	clean
	kave_install
	wait_for_ambari
    else
	if [ $AMBARI_TRIALS -ne 0 ]; then
	    echo "Ambari server is up and running! Enjoy!"
	    return 0
	else 
	    (>&2 echo "It was not possible to install and start Ambari server in 5 trials. See output and error log files for more details.")
	    return 3
	fi
    fi
}


function blueprint_deploy {
    #REST connection in deploy_from_blueprint.py can fail, so keep trying till success is reached
    local command="$BIN_DIR/blueprint_deploy.sh $VERSION ${KAVE_BLUEPRINT%.*} ${KAVE_CLUSTER%.*} $WORKING_DIR"
    # do not try more than 10 times before trying to do something else
    local count=5 
    $command
    while [ $? -ne 0 ] && test $count -ne 0; do 
	((count--))
	echo "Blueprint installation failed, retrying..."
	echo "Deployment attempts #"$count
	sleep 30
	$command
    done
    # try to re-install ambari in case deployment was not successful
    if [ $count -eq 0 ] && [ $blueprint_trials -ne 0 ]; then
	((BLUEPRINT_TRIALS--))
	echo "Blueprint deployment unsucessful. Reinstalling ambari server and retrying the deployment..."
	echo $BLUEPRINT_TRIALS" deployment trials remaining"
	pdsh -w "$CSV_HOSTS" "service ambari-agent stop; yum -y erase ambari-agent"
	clean
	kave_install
	blueprint_deploy
    else
	if [ $blueprint_trials -ne 0 ]; then
	    echo "deployment successful"
	    return 0
	else
	    (>&2 echo "It was not possible to deploy requested blueprint on your cluster. Please check if all machines in your cluster are running normally.")
	    return 3
	fi
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
    sleep 60
    cat /root/admin-password | kinit admin
    su -c "
        ipa user-mod $USER --password<<EOF
        $PASS
        $PASS
EOF"
    # let the changes propagate through the cluster
    sleep 120
}

function check_reinstall_restart_all {
    # checks if the deployment request succeeded. If not, triggers re-installation.
    local installation_status_message=$($command GET "$CLUSTERS_URL/$CLUSTER_NAME/requests/1?fields=Requests/request_status" 2> /dev/null)
    local failed=1
    if [[ "$installation_status_message" =~ "\"request_status\" : \"COMPLETED\"" ]]; then failed=0; fi
    if [ $failed -eq 0 ]; then
	echo "Congratulations! Everything is working on a first trial!"
    else 
	# first pass failed, so now reinstall
	echo "first pass failed, restarting all installations  and services"
	$WORKING_DIR/AmbariKave-$VERSION/dev/restart_all_services.sh 2>/dev/null
	# monitor and wait till the deployment finishes
	wait_on_deploy
	
	# # last request number
	# REQUEST_NUMBER=$($command GET "$CLUSTERS_URL/$CLUSTER_NAME/requests" 2>/dev/null | grep "id" | tail -n 1 | awk -F ':' '{print $2}' | awk -F ' ' '{print $1}')
	# local urllength=`echo "$CLUSTERS_URL/$CLUSTER_NAME/requests" | wc -m`
	# # first request number
	# REQUEST_NUMBER_2=$command GET "$CLUSTERS_URL/$CLUSTER_NAME/requests" 2>/dev/null | grep 'href' | grep 'requests/' | awk -F '"' '{print $4}' | sed -n 2p | sed -r 's/^.{$urllength}//'
	
}

function fix_freeipa_installation {
    local retries=30
    local failed=false
    #The FreeIPA client installation may fail, among other things, because of TGT negotiation failure (https://fedorahosted.org/freeipa/ticket/4808). On the version we are now if this happens the installation is not retried. The idea is to check on all the nodes whether FreeIPA clients are good or not with a simple smoke test, then proceed to retry the installation. A lot of noise is involved, mainly because of Ambari's not-so-shiny API and Kave technicalities.
    #Should be fixed by upgrading the version of FreeIPA, but unfortunately this is far in the future.
    #It is important anyway that we start to check after the installation has been tried at least once on all the nodes, so let's check for the locks and sleep for a while anyway.
    sleep 120
    count=5
    # first check if IPA server is up and running
    local host=$IPA_SERVER_NAME.`hostname -d`
    local host_url=$(echo $COMPONENTS_URL | sed "s/<HOST>/$host/g")
    local request="$CURL_AUTH_COMMAND GET $host_url/FREEIPA_SERVER?fields=HostRoles/state"
    local response=$($request)
    local state=$(echo "$response" | grep "\"state\" :" | awk -F '"' '{print $4}')
    if [ $state = STARTED ]; then 
	echo "IPA server started, checking clients..."
	# continue to the rest of the function
    else 
	echo "IPA server is not running, skipping client installation for the moment"
	return 0
    fi
    local kinit_pass_file=/root/admin-password
    local ipainst_lock_file=/root/ipa_client_install_lock_file
    until (pdsh -S -w "$CSV_HOSTS" "ls $ipainst_lock_file" && ls $kinit_pass_file 2>&-) || test $count -eq 0; do
	sleep 5
	((count--))
    done
    local kinit_pass=$(cat $kinit_pass_file)
    local pipe_hosts=$(echo "$CSV_HOSTS" | sed 's/localhost,\?//' | tr , '|')
    local ipacommand="ipa 1>/dev/null | wc -l"
    until local failed_hosts=$(pdsh -w "$CSV_HOSTS" "echo $kinit_pass | kinit admin" 2>&1 >/dev/null | sed -nr "s/($pipe_hosts): kinit:.*/\1.`hostname -d`/p" | tr '\n' , | head -c -1); test -z $failed_hosts; do
	if [ $retries -eq 0 ]; then
	    (>&2 echo "FreeIPA reinstall retries exceeded, you will have to install the IPA client yourself on the following nodes: '$failed_hosts'. Skipping...")
	    failed=true
	    break
	    fi
	((retries--))
	local command="$CURL_AUTH_COMMAND"
	local url="$COMPONENTS_URL/FREEIPA_CLIENT"
	pdsh -w "$failed_hosts" "rm -f $ipainst_lock_file; echo no | ipa-client-install --uninstall"
	pdcp -w "$failed_hosts" /root/robot-admin-password /root
	local target_hosts=($(echo $failed_hosts | tr , ' '))
	local install_request='{"RequestInfo":{"context":"Install"},"Body":{"HostRoles":{"state":"INSTALLED"}}}'
	local start_request=$(echo "$install_request" | sed -e "s/Install/Start/g" -e "s/INSTALLED/STARTED/g")
	for host in ${target_hosts[@]}; do
	    local host_url=$(echo $url | sed "s/<HOST>/$host/g")
	    $command DELETE $host_url
	    sleep 10
	    $command POST $host_url
	    sleep 10
	    $command PUT -d "$install_request" "$host_url"
	    sleep 10
	    $command PUT -d "$start_request" "$host_url"
	    sleep 10
	    # sometimes the ipa configuration may fail on some nodes. Try to do automatic reconfiguration
	    local ipamisconfig=`ssh $host $ipacommand`
	    if [ $ipamisconfig -ne 0 ]; then
		# command 'ipa' returned error that can mean misconfiguration
		local domain=`ssh $host "hostname -d"`
		local ipafixcommand="ipa-client-install -U -d --hostname=$host --domain=$domain --server=$IPA_SERVER_NAME.$domain -p admin -w $kinit_pass"
		ssh $host $ipafixcommand
            fi
	done
	sleep 120
    done
    if $failed; then return 3; fi
    
    return 0
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

wait_on_deploy

fix_freeipa_installation

enable_kaveadmin
