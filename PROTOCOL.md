# Benchmark protocol

The benchmark is conducted on three Supermicro bare-metal servers connected through a Supermicro 10Gbit switch. 
The servers are directly connected to the switch via DAC SFP+ passive cables and are set up in the same VLAN with jumbo frames activated (MTU 9000).

Kubernetes 1.19.0 is deployed via `kubeadm` on Ubuntu 18.04 and 20.40. Docker is setup with a standard `apt install docker.io` (so it will be version `19.03.6` on 18.04, and `19.03.8` on 20.04).

To improve reproducibility, we have chosen to always set up the master on the first node, to host the server part of the benchmark on the second server, and the client part on the third one. This is achieved via NodeSelector in Kubernetes deployments. 

The whole cluster is tear down and completely re-deployed between each CNI. Each CNI is tested 3 times, we retain the mean value.