# benchmark-k8s-cni-2020-08

This repository contains assets for the "Kubernetes CNI benchmark - August 2020" by infraBuilder (Twitter: @infrabuilder).

The benchmark is based on `knb` from the [k8s-bench-suite](https://github.com/InfraBuilder/k8s-bench-suite).

## Benchmark protocol

See [PROTOCOL.md](PROTOCOL.md)

## CNI selection

The CNI that are tested in this benchmark must be deployed with a "one yaml file" method. All CNIs yaml file used are present in the [cni](cni) directory. If a CNI need options to kubeadm init, like set the `--pod-network-cidr` for example, a file `{cni}.kopt` will contain the options used during the test.

## Run example

Please note that [benchmark.sh](benchmark.sh) uses [setup.sh](setup.sh), the node deployment script that is tailored for our MaaS-based lab environment. 

All benchmark runs are recorded in [Asciinema](https://asciinema.org/) :

```bash
export KERNEL=default
export DISTRIBUTION=18.04
export CNI=doc-antrea
asciinema rec results/$CNI.u$DISTRIBUTION-$KERNEL/$CNI.u$DISTRIBUTION-$KERNEL.cast -i 3 -c "./benchmark.sh"
EOF
```

Example :

[![asciicast](https://asciinema.org/a/NXrptSXsjqEeYQn4Hg1R7gb5O.png)](https://asciinema.org/a/NXrptSXsjqEeYQn4Hg1R7gb5O)

## Results 

### User friendly results 

Results for human being with charts and interpretation are available in an article on Medium. 

Work in progress ... Still writing it for now.

### Aggregated results

You can also check aggregated results on the spreadsheet here :
https://docs.google.com/spreadsheets/d/12dQqSGI0ZcmuEy48nA0P_bPl7Yp17fNg7De47CYWzaM/edit

Values injected in the spreadsheet are in files `results/<cni>.<distrib>-<kernel>/<cni>.<distrib>-<kernel>-run<x>.tsv`

### Raw results

Raw results are available in this repository, just check the [results](results) directory for `*.knbdata` files. 
You can generate reports with [knb](https://github.com/InfraBuilder/k8s-bench-suite), for example :

```bash
knb -fd results/doc-antrea.u18.04-default/doc-antrea.u18.04-default-run1.knbdata -o text
# or
knb -fd results/doc-antrea.u18.04-default/doc-antrea.u18.04-default-run1.knbdata -o json
# or
knb -fd results/doc-antrea.u18.04-default/doc-antrea.u18.04-default-run1.knbdata -o yaml
```

As `knbdata` files are just simple tar.gz archives, you can also uncompress the file to see raw containers logs (showing data even before being parsed by `knb`)
