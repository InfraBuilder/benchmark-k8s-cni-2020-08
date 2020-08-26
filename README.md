# benchmark-k8s-cni-2020-08

This repository contains assets for the "Kubernetes CNI benchmark - August 2020" by infraBuilder (Twitter: @infrabuilder).

The benchmark is based on `knb` from the [k8s-bench-suite](https://github.com/InfraBuilder/k8s-bench-suite).

## Benchmark protocol

The benchmark is conducted on three Supermicro bare-metal servers connected through a Supermicro 10Gbit switch. 
The servers are directly connected to the switch via DAC SFP+ passive cables and are set up in the same VLAN with jumbo frames activated (MTU 9000).

Kubernetes 1.19.0 is deployed via `kubeadm` on Ubuntu 18.04 and 20.40. Docker is setup with a standard `apt install docker.io` (so it will be version `` on 18.04, and `` on 20.04).

To improve reproducibility, we have chosen to always set up the master on the first node, to host the server part of the benchmark on the second server, and the client part on the third one. This is achieved via NodeSelector in Kubernetes deployments. 

The whole cluster is tear down and completely re-deployed between each CNI. Each CNI is tested 3 times, we retain the mean value.

The first round is made of "Out of documentation" CNI configuration. This would

## CNI selection

The CNI that are tested in this benchmark must be deployed with a "one yaml file" method. All CNIs yaml file used are present in the [cni](cni) directory. If a CNI need to set the `--pod-network-cidr` to kubeadm init, a file `{cni}.cidr` will contain the CIDR used during the test.

## Run example

All benchmark runs are recorded in Asciinema :

```bash
export KERNEL=default
export DISTRIBUTION=18.04
export CNI=doc-antrea
asciinema rec results/$CNI.u$DISTRIBUTION-$KERNEL.cast -i 3 -c "./benchmark.sh"
EOF
```

Example :

[![asciicast](https://asciinema.org/a/NXrptSXsjqEeYQn4Hg1R7gb5O.png)](https://asciinema.org/a/NXrptSXsjqEeYQn4Hg1R7gb5O)

## Results 

### User friendly results 

Results for human being with charts and interpretation are available in an article on Medium. Still writing it for now.

### Aggregated results

You can also check aggregated results on the spreadsheet here :
https://docs.google.com/spreadsheets/d/12dQqSGI0ZcmuEy48nA0P_bPl7Yp17fNg7De47CYWzaM/edit

Values injected in the spreadsheet are in files `cni/<cni>.<distrib>-<kernel>.tsv`

### Raw results

Raw results are available in this repository, just check the [results](results) directory for `*.knbdata` files. 
You can generate reports with [knb](https://github.com/InfraBuilder/k8s-bench-suite), for example :

```bash
knb -fd results/doc-antrea.u18.04-default-run1.knbdata -o text
# or
knb -fd results/doc-antrea.u18.04-default-run1.knbdata -o json
# or
knb -fd results/doc-antrea.u18.04-default-run1.knbdata -o yaml
```

As `knbdata` files are just simple tar.gz archives, you can also uncompress the file to see raw containers logs (showing data even before being parsed by `knb`)
