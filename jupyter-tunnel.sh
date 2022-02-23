#!/bin/bash
# Title: jupyter-tunnel.sh
# Version: 3.0
# Author: Frédéric CHEVALIER <fcheval@txbiomed.org>
# Created in: 2017-11-05
# Modified in: 2022-02-22
# Licence : GPL v3



#======#
# Aims #
#======#

aim="Create a SSH tunnel to connect to Jupyter server running remotely and start the internet browser."



#==========#
# Versions #
#==========#

# v3.0 - 2021-02-22: handle unlimited number of hosts instead of 2 hosts only / update argument names because of conflicts
# v2.3 - 2021-07-30: detection of lab server added
# v2.2 - 2021-01-07: bug related to local port detection corrected / bug related to socket and multiple connections corrected
# v2.1 - 2020-12-23: bug related to connection closing corrected / connection testing added / unnecessary code removed
# v2.0 - 2020-12-14: option to reach server running on a node of GE added
# v1.3 - 2020-04-21: no browser option added
# v1.2 - 2020-04-07: detection of jupyter improved
# v1.1 - 2019-12-12: sshpass added / bind message error solved by using ssh -4
# v1.0 - 2018-07-28: script renamed / help message and options added / ssh-agent check added / ssh-agent forcing option added / SSH option updated / safety bash script options
# v0.1 - 2018-04-29: use of a socket for SSH tunnel
# v0.0 - 2017-11-05: creation

version=$(grep -i -m 1 "version" "$0" | cut -d ":" -f 2 | sed "s/^ *//g")



#===========#
# Functions #
#===========#

# Usage message
function usage {
    echo -e "
    \e[32m ${0##*/} \e[00m -s|--host host(s) -n|--node name -b|--browser path -a|--ssha -p|--sshp -h|--help

Aim: $aim

Version: $version

Options:
    -s,  --host     host (or list of hosts, space separated) to be contacted to reach the Jupyter server.
                        If a list, the order must correspond to the order in which hosts must be contacted.
    -b,  --browser  path to the internet browser to start after connection is up [default: firefox]
                        \"n\" or \"none\" prevent starting the browser.
    -n,  --node     node of the Grid Engine cluster running the Jupyter server (optional)
    -a,  --ssha     force the creation of a new ssh agent
    -p,  --pass     use sshpass to store ssh password
    -h,  --help     this message
    "
}


# Info message
function info {
    if [[ -t 1 ]]
    then
        echo -e "\e[32mInfo:\e[00m $1"
    else
        echo -e "Info: $1"
    fi
}


# Warning message
function warning {
    if [[ -t 1 ]]
    then
        echo -e "\e[33mWarning:\e[00m $1"
    else
        echo -e "Warning: $1"
    fi
}


# Error message
## usage: error "message" exit_code
## exit code optional (no exit allowing downstream steps)
function error {
    if [[ -t 1 ]]
    then
        echo -e "\e[31mError:\e[00m $1"
    else
        echo -e "Error: $1"
    fi

    if [[ -n $2 ]]
    then
        exit $2
    fi
}


# Dependency test
function test_dep {
    which $1 &> /dev/null
    if [[ $? != 0 ]]
    then
        error "$1 not found. Exiting..." 1
    fi
}




#==============#
# Dependencies #
#==============#

test_dep ssh
test_dep curl



#===========#
# Variables #
#===========#

# Options
while [[ $# -gt 0 ]]
do
    case $1 in
        -s|--host    ) host=("$2") ; shift 2
                            while [[ -n "$1" && ! "$1" =~ ^- ]]
                            do
                                host+=("$1")
                                shift
                            done ;;
        -b|--browser ) browser="$2" ; shift 2 ;;
        -n|--node    ) node="$2"    ; shift 2 ;;
        -a|--ssha    ) ssha=1       ; shift   ;;
        -p|--sshp    ) sshp=1       ; shift   ;;
        -h|--help    ) usage ; exit 0 ;;
        *            ) error "Invalid option: $1\n$(usage)" 1 ;;
    esac
done


# Check for mandatory options
[[ -z "$host" ]] && error "Server address missing for ssh connection. Exiting..." 1

# Default browser
[[ -z "$browser" ]] && browser=firefox

# Test existence of the browser
[[ "$browser" != n && "$browser" != none ]] && test_dep "$browser"

# SHH agent
[[ -z "$SSH_AUTH_SOCK" || -n "$ssha" ]] && sshk=1 && eval $(ssh-agent) &> /dev/null

# SSH password
if [[ -n "$sshp" ]]
then
    test_dep sshpass
    read -sp "Enter SSH password: " SSHPASS
    export SSHPASS
    echo ""
    myssh="sshpass -e ssh"
else
    myssh=ssh
fi



#============#
# Processing #
#============#

# Check connectivity
mytest=$($myssh -q -A -4 ${host[0]} echo 0)
[[ -z "$mytest" ]] && error "Wrong password or no connection. Exiting..." 1

# Update host list to include -J if needed
[[ ${#host[@]} -gt 1 ]] &&  host="-J $(echo ${host[@]} | rev | sed "s/ /,/2g" | rev)"

# Set bash options to stop script if a command exit with non-zero status
set -e
set -o pipefail

if [[ -z "$node" ]]
then
    # List Jupyter servers
    mysvr=$($myssh -q -A -o AddKeysToAgent=yes -4 $host "\$(ps -u \$USER -o command | grep -E \"jupyter-(notebook|lab)\" | grep -v grep | cut -d \" \" -f -2) list 2> /dev/null | tail -n +2 | cut -d \" \" -f 1")

    # Check how many Jupyter servers are running
    [[ -z "$mysvr" ]] && error "No server is running. Exiting..." 1
    [[ $(wc -l <<< "$mysvr") -gt 1 ]] && error "More than one server is running. Exiting..." 1
else
    # Connect to the node and get username and PID of the Jupyter server (set +/-e to deactivate/reactivate error check otherwise script exits if no notebook)
    set +e
    myvar=$($myssh -q -A -o AddKeysToAgent=yes -4 $host "ssh $node 'echo \$USER ; pgrep -u \$USER -f jupyter-[notebook-lab]'")
    set -e
    
    # Split variable values
    myuser=$(head -n 1 <<< $myvar)
    mypid_j=$(tail -n +2 <<< $myvar)

    # Check how many Jupyter servers are running
    [[ -z "$mypid_j" ]] && error "No server is running. Exiting..." 1
    [[ $(wc -l <<< "$mypid_j") -gt 1 ]] && error "More than one server is running. Exiting..." 1

    # Get server address from the notebook connection file
    ## Note: runtime folder can be obtained using jupyter --path 
    mysvr=$($myssh -q -A -o AddKeysToAgent=yes -4 $host "cat \$HOME/.local/share/jupyter/runtime/*server-$mypid_j-open.html | grep \"a href\" | cut -d \"\\\"\" -f 2")

    # Replace node with localhost
    mysvr=$(sed -r "s|(^h.*/).*(:.*$)|\1localhost\2|" <<< "$mysvr")
fi

# Identify port and token
myport_j=$(echo "$mysvr" | cut -d ":" -f 3 | cut -d "/" -f 1)

# Select port on localhost
port_list=$(netstat -ant | tail -n +3 | sed "s/  */\t/g" | cut -f 4 | cut -d ":" -f 2 | sort | uniq)
for ((i=$myport_j ; i <= 40000 ; i++))
do
    [[ $(echo "$port_list" | grep -w $i) ]] || break
done
myport_l=$i
info "Port used on localhost: $myport_l"

[[ $myport_l != $myport_j ]] && mysvr=$(echo "$mysvr" | sed "s;:$myport_j/;:$myport_l/;")

# Edit host for node connection
[[ -n "$node" ]] && host=$(sed "s/ /,/2g" <<< "$host")

mysocket=/tmp/${USER}_jupyter_socket_$RANDOM

# Create tunnel (must deactivate set -e using set +e otherwise script exits)
## Note: sshpass does not handle ssh -f is when jump host is used (source: https://serverfault.com/a/1005485)
set +e

if [[ -z "$node" ]]
then
    $myssh -q -M -S $mysocket -A -o ServerAliveInterval=60 -L ${myport_l}:localhost:${myport_j} $host -N &
else
    $myssh -q -M -S $mysocket -A -o ServerAliveInterval=60 -L ${myport_l}:$node:${myport_j} $host -N $myuser@$node &
fi

# Create trap to close ssh tunnel when interrupt
trap "$myssh -q -S $mysocket -O exit $host $node" SIGINT SIGTERM

# Check connectivity (as the tunnel is not set with -f)
count=0
while [[ $(curl -s "$mysvr" ; echo $?) -ne 0 ]]
do
    sleep 1s
    ((count++))
    [[ $count -gt 100 ]] && warning "Connection to $mysvr is not yet established. You may wait a little longer or restart the script." && break
done

# Start Jupyter page
if [[ "$browser" != n && "$browser" != none ]]
then
    echo "$mysvr"
    info "Opening the browser tab..."
    sleep 2s
    $browser "$mysvr" &
fi

# Wait until interruption
info "Once done with Jupyter, use Ctrl-C to close the SSH tunnel..."

sleep inf

# Reactivate error detection
set -e

# Kill SSH agent if it was started with the script
[[ -n "$sshk" ]] && ssh-agent -k

exit 0
