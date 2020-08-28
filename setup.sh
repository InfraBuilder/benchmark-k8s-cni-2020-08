#!/bin/bash

DEBUG_LEVEL=3

[ "$(tput colors)" -gt 0 ] && COLOR="true" || COLOR="false"
function color { 
	$COLOR || return 0
	color="0"
	case $1 in
		normal) color="0" ;;
		rst) color="0" ;;
		red) color="31" ;;
		green) color="32" ;;
		yellow) color="33" ;;
		blue) color="34" ;;
		magenta) color="35" ;;
		cyan) color="36" ;;
		lightred) color="91" ;;
		lightgreen) color="92" ;;
		lightyellow) color="93" ;;
		lightblue) color="94" ;;
		lightmagenta) color="95" ;;
		lightcyan) color="96" ;;
		white) color="97" ;;
		*) color="0" ;;
	esac
	echo -e "\033[0;${color}m"
}
function logdate { date "+%Y-%m-%d %H:%M:%S"; }
function fatal { echo "$(logdate) $(color red)[FATAL]$(color normal) $@" >&2; exit 1; }
function err { echo "$(logdate) $(color lightred)[ERROR]$(color normal) $@" >&2; }
function warn { [$DEBUG_LEVEL -ge 1 ] && echo "$(logdate) $(color yellow)[WARNING]$(color normal) $@" >&2; }
function info { [ $DEBUG_LEVEL -ge 2 ] && echo "$(logdate) $(color cyan)[INFO]$(color normal) $@" >&2; }
function debug { [ $DEBUG_LEVEL -ge 3 ] && echo "$(logdate) $(color lightcyan)[DEBUG]$(color normal) $@" >&2; }


function maas_id { maas ubuntu nodes read | jq '.[] | select(.hostname=="'$1'") | .system_id' -r ;}
function maas_status { maas ubuntu nodes read hostname=$1| grep '"status_name"'| cut -d '"' -f 4; }
function maas_release { maas ubuntu machine release $(maas_id $1) > /dev/null; }
function maas_deploy { host=$1; shift; maas ubuntu machine deploy $(maas_id $host) $@ > /dev/null; }
function maas_wait_status {
    STATUS=$1
    shift
    HOSTS=$@
    PIDLIST=""

    for i in $HOSTS
    do
        ( while [ "$(maas_status $i)" != "$STATUS" ]; do sleep 1; done ) &
        PIDLIST="$PIDLIST $!"
    done

    wait $PIDLIST
}

function qscp { scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $@; }
function qssh { ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $@; }
function lssh { HOST=$(sed 's/^[^1-9]*//' <<< "$1"); shift; qssh ubuntu@10.1.1.$HOST $@; }
function lssh_wait {
    HOSTS=$@
    PIDLIST=""

    for i in $HOSTS
    do
        ( while [ "$(lssh $i sudo whoami 2>/dev/null)" != "root" ]; do sleep 1; done ) &
        PIDLIST="$PIDLIST $!"
    done

    wait $PIDLIST
}

function usage {
	echo "Usage : $0 --cni cni -m master -w worker -w worker [...]"
	echo "Plugin list available :"
	cd cni/
	ls -1 | grep -E '.*yml$'| sed -e 's/.yml$//' -e 's/^/ - /'
	exit
}


#==============================================================================
# Argument parsing
#==============================================================================

[ "$1" = "" ] && usage && exit

cd $(dirname $0)

DISTRIBUTION="bionic"
KERNEL="default"
RELEASE="false"
CUSTOM_MTU="9000"

MASTER="s02"
WORKERS="s03 s04"

UNKNOWN_ARGLIST=""
while [ "$1" != "" ]
do
	arg=$1
	case $arg in
		
		--cni|-c)
			shift
			[ "$1" = "" ] && fatal "$arg flag must be followed by a value"
			CNI_TO_SETUP=$1
			info "CNI will be '$CNI_TO_SETUP'"
			;;

        --master|-m)
			shift
			[ "$1" = "" ] && fatal "$arg flag must be followed by a value"
			MASTER=$1
			info "Master node will be '$MASTER'"
			;;

        --worker|-w)
			shift
			[ "$1" = "" ] && fatal "$arg flag must be followed by a value"
			WORKERS="$(sed 's/,/ /g' <<< $1)"
			info "Worker nodes will be '$WORKERS'"
			;;

		--mtu)
			shift
			[ "$1" = "" ] && fatal "$arg flag must be followed by a value"
			CUSTOM_MTU=$1
			info "MTU will be '$CUSTOM_MTU'"
			;;

        --distrib|-d)
			shift
			[ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            case "$1" in
                
                bionic) DISTRIBUTION="bionic" ;;
                u18.04) DISTRIBUTION="bionic" ;;
                18.04) DISTRIBUTION="bionic" ;;
                u18)    DISTRIBUTION="bionic" ;;

                focal) DISTRIBUTION="focal" ;;
                u20.04) DISTRIBUTION="focal" ;;
                20.04) DISTRIBUTION="focal" ;;
                u20)    DISTRIBUTION="focal" ;;
                
                *) fatal "$1 is not a valid distribution" ;;
            esac
			info "Distribution node will be '$DISTRIBUTION'"
			;;

        --kernel|-k)
			shift
			[ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            case "$1" in
                default) KERNEL="default" ;;
                hwe) KERNEL="hwe" ;;
                egde) KERNEL="edge" ;;
                *) fatal "" ;;
            esac
			info "Kernel node will be '$KERNEL'"
			;;

        --release|-r)
			RELEASE="true"
			info "release instead of deploying"
			;;

        # Unknown flag
		*) UNKNOWN_ARGLIST="$UNKNOWN_ARGLIST $arg" ;;
	esac
	shift
done

[ "$UNKNOWN_ARGLIST" != "" ] && fatal "Unknown arguments : $UNKNOWN_ARGLIST"
$DEBUG && debug "Argument parsing done"
#==============================================================================
# Pre-flight checks
#==============================================================================

[ "$MASTER" = "" ] && fatal "You must specify a master node with flag --master or -m"
[ "$WORKERS" = "" ] && fatal "You must specify at least one worker node with flag --worker or -w"

$DEBUG && debug "master and workers defined"
NODES="$MASTER $WORKERS"

if $RELEASE
then
    for i in $NODES
    do
        info "Releasing node $i"
        maas_release $i
    done
    exit
fi


$DEBUG && debug "CNI check"

[ "$CNI_TO_SETUP" = "" ] && fatal "You must specify a CNI to setup with flag --cni or -c"
case $CNI_TO_SETUP in
	nok8s)
		info "Will not deploy k8s"
		;;
	nocni)
		info "Will not deploy cni"
		;;
	*)
		[ -e "cni/$CNI_TO_SETUP.yml" ] || fatal "Unkown network plugin '$CNI_TO_SETUP'"
		;;
esac

#==============================================================================
# Deployment
#==============================================================================

REALKERNEL=""
case $DISTRIBUTION in
    bionic)
        case "$KERNEL" in
            default) REALKERNEL="ga-18.04" ;;
            hwe) REALKERNEL="hwe-18.04" ;;
            edge) REALKERNEL="hwe-18.04-edge" ;;
            *) fatal "" ;;
        esac
        ;;
    focal)
        case "$KERNEL" in
            default) REALKERNEL="ga-18.04" ;;
            hwe) fatal "There is no hwe kernel for $DISTRIBUTION" ;;
            edge) fatal "There is no edge kernel for $DISTRIBUTION" ;;
            *) fatal "" ;;
        esac
        ;;
    *)
        fatal "Unknown distribution $DISTRIBUTION"
        ;;
esac

info "Starting deployment of k8s with plugin $CNI_TO_SETUP"
info " ( MASTER = $MASTER and WORKERS = $WORKERS )"

info "Waiting for nodes to be ready"
maas_wait_status Ready $NODES

info "Deploying nodes with Ubuntu $DISTRIBUTION with kernel $KERNEL ($REALKERNEL)"
for i in $NODES
do
	maas_deploy $i distro_series=$DISTRIBUTION hwe_kernel=$REALKERNEL
done
info "Waiting for nodes to be deployed"
maas_wait_status Deployed $NODES

info "Waiting for SSH access"
lssh_wait $NODES

info "Preparing nodes"
PIDLIST=""
for h in $NODES
do
	(
	info "Node $h start"
	cat <<-EOF | lssh $h "sudo bash" >/tmp/setup.$h.out 2>/tmp/setup.$h.err
	if [ -e "/etc/netplan/50-cloud-init.yaml" ]
	then
		sed -i 's/mtu: 1500/mtu: $CUSTOM_MTU/' /etc/netplan/50-cloud-init.yaml
		netplan apply
	else
		sed -i 's/mtu 1500/mtu $CUSTOM_MTU/'  /etc/network/interfaces.d/50-cloud-init.cfg
		systemctl restart networking
	fi

	sed -i 's/nameserver .*/nameserver 8.8.8.8/' /etc/resolv.conf
	( 
		echo "10.1.1.2 s02"
		echo "10.1.1.3 s03"
		echo "10.1.1.4 s04"
		echo "10.1.1.5 g05"
		echo "10.1.1.101 m01"
		echo "10.1.1.102 m02"
		echo "10.1.1.103 m03"
		echo "10.1.1.104 m04"
		echo "10.1.1.105 m05"
		echo "10.1.1.106 m06"
		echo "10.1.1.107 m07"
		echo "10.1.1.108 m08"
		echo "10.1.1.109 m09"
		echo "10.1.1.110 m10"
		echo "10.1.1.111 m11"
		echo "10.1.1.112 m12"
	) >> /etc/hosts

	# Preparing apt
	apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
	apt-get update

	# Setup kube* cli
	apt-get install -y kubelet kubeadm kubectl docker.io
	swapoff -a
	sed -i '/\sswap\s/d' /etc/fstab

	# Mounting eBPF FS
	mount bpffs /sys/fs/bpf -t bpf

	EOF

	info "Node $h end"
	) &
	PIDLIST="$PIDLIST $!"
done
wait $PIDLIST

[ "$CNI_TO_SETUP" = "nok8s" ] && info "Skipping Kubernetes " && exit

#===[ K8S Master Setup ]=======================================================

info "Deploying master"

KOPT=""
[ -e "cni/$CNI_TO_SETUP.kopt" ] && KOPT="$(cat cni/$CNI_TO_SETUP.kopt)"
[ "$KOPT" != "" ] && info "Using master option $KOPT"
lssh $MASTER sudo kubeadm init $KOPT >/dev/null 2> /dev/null

#===[ K8S Worker Setup ]=======================================================

info "Generating join command"
JOINCMD="$(lssh $MASTER sudo kubeadm token create --print-join-command 2>/dev/null)"
debug "Join command is $JOINCMD"

info "Retrieving kubeconfig"
lssh $MASTER sudo cat /etc/kubernetes/admin.conf > kubeconfig 2>/dev/null

sleep 10

info "Joining nodes"
for i in $WORKERS
do
	lssh $i sudo $JOINCMD > /dev/null 2>/dev/null
done

export KUBECONFIG="$(pwd)/kubeconfig"

#===[ CNI Setup ]==============================================================

if [ "$CNI_TO_SETUP" = "nocni" ] 
then
    info "Cluster is ready with no CNI"
    exit 0
fi

info "Installing CNI $CNI_TO_SETUP"
kubectl apply -f cni/$CNI_TO_SETUP.yml >/dev/null

info "Waiting for all nodes to be ready"
for i in $NODES
do
	info "  Waiting for node $i to be ready"
	while true
	do

		kubectl get node $i | grep "NotReady" >/dev/null || break
		sleep 1
	done
done
info "Cluster is now ready with network CNI $CNI_TO_SETUP"