# jupyter-tunnel

The purpose of this script is to connect to a remote [Jupyter notebook](https://jupyter.org/) (or JupyterLab) server through an SSH tunnel. Jupyter notebooks are informatics notebooks that allow executing code and giving context, with the goal of keeping records and improving reproducibility. When a Jupyter server is running remotely, you can connect to it by opening a remote web browser. However, this is usually slow (especially if connection is bad), consumes unnecessary server resources, and forces you to have an additional web browser opened. The tunnel created by this script avoids this by allowing your local browser to connect to the remote server and sending the needed information through the tunnel.

In addition to connecting to Jupyter server on a standalone remote server, this script allows connection to Jupyter server running on a node of a Grid Engine cluster.

The script is designed to access the remote server/node through a gateway server. For the moment, there is no option to skip the gateway server.


## Dependencies

The only mandatory dependency is SSH.

An optional dependency is sshpass. If the gateway you connect to does not support SSH keys but only password, this utility will avoid entering your password each time the script has to connect to fetch information (and it does it a fair number of times). The use of sshpass is triggered by a script option (see [usage](#usage)). This package can be installed on your system using your package manager.


## Installation

To download the latest version of the script:
```
git clone https://github.com/fdchevalier/jupyter-tunnel
```

For convenience, the script should be accessible system-wide by either including the folder in your `$PATH` or by moving the scripts in a folder present in your path (e.g. `$HOME/.local/bin/`).


## Usage

A summary of available options can be obtained using `jupyter-tunnel.sh -h`.
```
$ jupyter-tunnel.sh -h

     jupyter-tunnel.sh  -h1|--host1 host -h2|--host2 host2 -n|--node name -b|--browser path -s|--ssha -p|--sshp -h|--help

Aim: Create a SSH tunnel to connect to Jupyter server running remotely and start the internet browser.

Version: 2.3

Options:
    -h1, --host1    first host to connect to set the tunnel up
    -h2, --host2    second host to connect on which Jupyter server is running
    -b,  --browser  path to the internet browser to start after connection is up [default: firefox]
                        "n" or "none" prevent starting the browser.
    -n,  --node     node of the Grid Engine cluster running the Jupyter server (optional)
    -s,  --ssha     force the creation of a new ssh agent
    -p,  --pass     use sshpass to store ssh password
    -h,  --help     this message
```

Notes:
* If you wish to use the web browser option, make sure that the web browser is accessible through the command line from your `$PATH` variable.
* `-b n` is useful if you use to reload previous session or pin the Jupyter tab. Be aware that if the local port change, you will need to manually update it in the address bar.
* When connecting to a Grid Engine node, the node name must be entered using the `-n` option. There is no way to determine this automatically.


### Examples

There are two cases that you can encounter:
* The Jupyter server is running on a remote server accessible through a gateway server. In this case, the basic command will be: `jupypter-tunnel.sh -h1 user@gateway.ext -h2 user@server.ext`
* The Jupyter server is running on a node of a Grid Engine cluster accessible through a gateway server. In this case, the basic command will be: `jupypter-tunnel.sh -h1 user@gateway.ext -h2 user@head-node.ext -n server-node.local`

Note: the `user@server` can be simplified to `server` if you use a SSH config file or if the username of your local machine is the same as the one on the remote machine.


## Companion scripts

* `jupyter-tunnel-shutdown.sh`: this script sends an interruption signal to any jupyter-tunnel processes. This is equivalent to Ctrl+C used to close the tunnel. This script can be to automatize tunnel shutdown on sleep for instance in order to make sure that port on server will be released.
* `jupyter-node.sh`: this script starts a Jupyter server on a node of a SGE cluster from the head node. 


## License

This project is licensed under the [GPLv3](LICENSE).
