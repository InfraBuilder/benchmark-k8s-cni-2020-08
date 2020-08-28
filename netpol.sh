#!/bin/bash

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
DEBUG_LEVEL=2
function logdate { date "+%Y-%m-%d %H:%M:%S"; }
function fatal { echo "$(logdate) $(color red)[FATAL]$(color normal) $@" >&2; exit 1; }
function err { echo "$(logdate) $(color lightred)[ERROR]$(color normal) $@" >&2; }
function warn { [ $DEBUG_LEVEL -ge 1 ] && echo "$(logdate) $(color yellow)[WARNING]$(color normal) $@" >&2; }
function info { [ $DEBUG_LEVEL -ge 2 ] && echo "$(logdate) $(color cyan)[INFO]$(color normal) $@" >&2; }
function debug { [ $DEBUG_LEVEL -ge 3 ] && echo "$(logdate) $(color lightcyan)[DEBUG]$(color normal) $@" >&2; }


kubectl get ns netpol 2>/dev/null && echo "Existing netpol namespace, aborting ..." && exit

K="kubectl run -n netpol --restart=Never"

info "Initializing"
kubectl apply -f - <<EOF > /dev/null
apiVersion: v1
kind: Namespace
metadata:
  creationTimestamp: null
  name: netpol
spec: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-ingress
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      run: server-with-netpol
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          run: authorized-client # Authorized Client
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-egress
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      run: client-with-netpol
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          run: authorized-server
EOF

# Starting server
function start_srv {
	NAME=$1
	$K $NAME --image=infrabuilder/netbench:server-http >/dev/null 2>/dev/null
	while true; do kubectl -n netpol get pod/$NAME |grep Running >/dev/null && break; sleep 1; done
	sleep 1
	kubectl get -n netpol pod/$NAME -o jsonpath='{.status.podIP}'
}
function client {
	NAME=$1
	SRVIP=$2
	$K -it --rm --image=infrabuilder/netbench:client \
	$1 -- sh -c "sleep 5; curl --connect-timeout 5 $2" 2>/dev/null | grep "Welcome to nginx" > /dev/null && echo yes || echo no
}
function del {
	NAME=$1
	kubectl -n netpol delete po/$NAME 2>/dev/null >/dev/null
}

info "Starting ingress/egress tests"
#=====================================================
# Egress
#=====================================================
# Scenario :
#
# A server pod with ingress netpol should be accessed
# by an authorized client, but should not be accessed
# by a 'not authorized' client
#
# +-------------------+              +------------------+
# | Authorized client +---------+--->+Server with netpol|
# +-------------------+         |    +------------------+
#                               |
# +-------------------+         |
# |Unauthorized client+-----X---+
# +-------------------+
#=====================================================

# Ingress
IP=$(start_srv server-with-netpol)
INGRESS=no
if [ "$(client authorized-client $IP)" = "yes" ]
then
	info "INGRESS [1/2] SUCCESS: 'Authorized' client 'can' access protected server"
	if [ "$(client unauthorized-client $IP)" = "no" ]
	then
		info "INGRESS [2/2] SUCCESS: 'Unauthorized' client 'cannot' access protected server"
		INGRESS=yes
	else
		warn "INGRESS [2/2] FAIL: 'Unauthorized' client 'can' access protected server"
	fi
else
	warn "INGRESS [1/2] FAIL: 'Authorized' client cannot access protected server"
fi
del server-with-netpol

#=====================================================
# Egress
#=====================================================
# Scenario :
#
# A client pod with egress netpol should access to
# an authorized server, but should not access to a
# 'not authorized' server
#
# +------------------+          +-------------------+
# |Client with netpol+--+------>+ Authorized server |
# +------------------+  |       +-------------------+
#                       |
#                       |       +-------------------+
#                       +--X--> |Unauthorized server|
#                               +-------------------+
#=====================================================
IPA=$(start_srv authorized-server)
IPU=$(start_srv unauthorized-server)
EGRESS=no

if [ "$(client client-with-netpol $IPA)" = "yes" ]
then
	info "EGRESS [1/2] SUCCESS: Protected client 'can' access 'authorized' server"
	if [ "$(client client-with-netpol $IPU)" = "no" ]
	then
		info "EGRESS [2/2] SUCCESS: Protected client 'cannot' access 'unauthorized' server"
		EGRESS=yes
	else

		warn "EGRESS [2/2] FAIL: Protected client 'can' access 'unauthorized' server"
	fi
else
	warn "EGRESS [1/2] FAIL: Protected client 'cannot' access 'authorized' server"
fi
del authorized-server
del unauthorized-server

info "Cleaning"
kubectl delete ns netpol >/dev/null


echo -e "Ingress\tEgress"
echo -e "$INGRESS\t$EGRESS"