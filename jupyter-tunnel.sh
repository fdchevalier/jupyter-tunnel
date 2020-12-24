#!/bin/bash
# Title: jupyter-tunnel.sh
# Version: 2.1
# Author: Frédéric CHEVALIER <fcheval@txbiomed.org>
# Created in: 2017-11-05
# Modified in: 2020-12-23
# Licence : GPL v3



#======#
# Aims #
#======#

aim="Create a SSH tunnel to connect to Jupyter notebook server running remotely and start the internet browser."



#==========#
# Versions #
#==========#

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
    \e[32m ${0##*/} \e[00m -h1|--host1 host -h2|--host2 host2 -n|--node name -b|--browser path -s|--ssha -p|--sshp -h|--help

Aim: $aim

Version: $version

Options:
    -h1, --host1    first host to connect to set the tunnel up
    -h2, --host2    second host to connect on which Jupyter server is running
    -b,  --browser  path to the internet browser to start after connection is up [default: firefox]
                        \"n\" or \"none\" prevent starting the browser.
    -n,  --node     node of the Grid Engine cluster running the Jupyter server (optional)
    -s,  --ssha     force the creation of a new ssh agent
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



#===========#
# Variables #
#===========#

# Options
while [[ $# -gt 0 ]]
do
    case $1 in
        -h1|--host1  ) host1="$2"   ; shift 2 ;;
        -h2|--host2  ) host2="$2"   ; shift 2 ;;
        -b|--browser ) browser="$2" ; shift 2 ;;
        -n|--node    ) node="$2"    ; shift 2 ;;
        -s|--ssha    ) ssha=1       ; shift   ;;
        -p|--sshp    ) sshp=1       ; shift   ;;
        -h|--help    ) usage ; exit 0 ;;
        *            ) error "Invalid option: $1\n$(usage)" 1 ;;
    esac
done


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
mytest=$($myssh -q -A -4 $host1 echo 0)
[[ -z "$mytest" ]] && error "Wrong password or no connection. Exiting..." 1


# Set bash options to stop script if a command exit with non-zero status
set -e
set -o pipefail

if [[ -z "$node" ]]
then
    # List Jupyter servers
    mysvr=$($myssh -q -A -o AddKeysToAgent=yes -4 $host1 "ssh $host2 '\$(ps -u \$USER -o command | grep jupyter-notebook | grep -v grep | cut -d \" \" -f -2) list 2> /dev/null | tail -n +2 | cut -d \" \" -f 1'")

    # Check how many Jupyter servers are running
    [[ -z "$mysvr" ]] && error "No server is running. Exiting..." 1
    [[ $(wc -l <<< "$mysvr") -gt 1 ]] && error "More than one server is running. Exiting..." 1
else
    # Connect to the node and get PID of the Jupyter server (set +/-e to deactivate/reactivate error check otherwise script exits if no notebook)
    set +e
    mypid_j=$($myssh -q -A -o AddKeysToAgent=yes -4 $host1 "ssh $host2 ssh $node 'pgrep -f jupyter-notebook'")
    set -e
    
    # Check how many Jupyter servers are running
    [[ -z "$mypid_j" ]] && error "No server is running. Exiting..." 1
    [[ $(wc -l <<< "$mypid_j") -gt 1 ]] && error "More than one server is running. Exiting..." 1

    # Get server address from the notebook connection file
    ## Note: runtime folder can be obtained using jupyter --path 
    mysvr=$($myssh -q -A -o AddKeysToAgent=yes -4 $host1 "ssh $host2 'cat \$HOME/.local/share/jupyter/runtime/nbserver-$mypid_j-open.html | grep \"a href\" | cut -d \"\\\"\" -f 2'")

    # Replace node with localhost
    mysvr=$(sed -r "s|(^h.*/).*(:.*$)|\1localhost\2|" <<< "$mysvr")
fi

# Identify port and token
myport_j=$(echo "$mysvr" | cut -d ":" -f 3 | cut -d "/" -f 1)

# Select port on localhost
port_list=$(netstat -ant | tail -n +3 | sed "s/  */\t/g" | cut -f 3 | cut -d ":" -f 2 | sort | uniq)
for ((i=$myport_j ; i <= 40000 ; i++))
do
    [[ $(echo "$port_list" | grep -w $i) ]] || break
done
myport_l=$i
info "Port used on localhost: $myport_l"

[[ $myport_l != $myport_j ]] && mysvr=$(echo "$mysvr" | sed "s;:$myport_j/;:$myport_l/;")

# Select port on remote server (host1)
port_list=$($myssh -q $host1 'netstat -ant | tail -n +3 | sed "s/  */\t/g" | cut -f 4 | cut -d ":" -f 2 | sort | uniq')
for ((i=9999 ; i <= 40000 ; i++))
do
    [[ $(echo "$port_list" | grep -w $i) ]] || break
done
myport_r=$i
info "Port used for the SSH tunnel on $host1: $myport_r"

# Select port on remote server (host2)
if [[ -n "$node" ]]
then
    port_list=$($myssh -q -A -o AddKeysToAgent=yes -4 $host1 ssh $host2 'netstat -ant | tail -n +3 | sed "s/  */\t/g" | cut -f 4 | cut -d ":" -f 2 | sort | uniq')
    for ((i=9999 ; i <= 40000 ; i++))
    do
        [[ $(echo "$port_list" | grep -w $i) ]] || break
    done
    myport_r2=$i
    info "Port used for the SSH tunnel on $host2: $myport_r2"
fi

mysocket=/tmp/${USER}_jupyter_socket

# Create tunnel (must deactivate set -e using set +e otherwise script exits)
set +e

if [[ -z "$node" ]]
then
    $myssh -q -M -S $mysocket -fA -o ServerAliveInterval=60 -L ${myport_l}:localhost:${myport_r} $host1 ssh -4 -L ${myport_r}:localhost:${myport_j} -N $host2
else
    $myssh -q -M -S $mysocket -fA -o ServerAliveInterval=60 -L ${myport_l}:localhost:${myport_r} $host1 ssh -4 -L ${myport_r}:localhost:${myport_r2} $host2 ssh -4 -L ${myport_r2}:$node:${myport_j} -N $node
fi

# Close connections
function portk {
    [[ -z $4 ]] && $myssh -q -A $host1 "pkill -f \"ssh .*-L $2:localhost:$1 -N $host2\""
    [[ -n $4 ]] && $myssh -q -A $host1 ssh $host2 pkill -f \\\"ssh .*-L $3:$4:$1 -N $4\\\"
}

# Create trap to close ssh tunnel when interrupt
trap "$myssh -q -S $mysocket -O exit $host1 ; portk ${myport_j} ${myport_r} ${myport_r2} ${node}" SIGINT SIGTERM

# Start Jupyter page
if [[ "$browser" != n && "$browser" != none ]]
then
    echo "$mysvr"
    info "Opening the browser tab..."
    sleep 2s
    firefox "$mysvr" &
fi

# Wait until interruption
info "Once done with Jupyter, use Ctrl-C to close the SSH tunnel..."

sleep inf

# Reactivate error detection
set -e

# Kill SSH agent if it was started with the script
[[ -n "$sshk" ]] && ssh-agent -k

exit 0
