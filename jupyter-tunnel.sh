#!/bin/bash
# Title: jupyter-tunnel.sh
# Version: 1.1
# Author: Frédéric CHEVALIER <fcheval@txbiomed.org>
# Created in: 2017-11-05
# Modified in: 2019-12-12
# Licence : GPL v3



#======#
# Aims #
#======#

aim="Create a SSH tunnel to connect to Jupyter notebook server running remotely and start the internet browser."



#==========#
# Versions #
#==========#

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
    \e[32m ${0##*/} \e[00m -h1|--host1 host -h2|--host2 host2 -b|--browser path -j|--j_loc path -s|--ssha -p|--sshp -h|--help

Aim: $aim

Version: $version

Options:
    -h1, --host1    first host to connect to set the tunnel up
    -h2, --host2    second host to connect on which Jupyter server is running
    -b,  --browser  path to the internet browser to start after connection is up [default: firefox]
    -j,  --j_loc    path to the jupyer executable on host2 [default: \$HOME/local/bin/jupyter]
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
        error "Package $1 is needed. Exiting..." 1
    fi
}




#==============#
# Dependencies #
#==============#

test_dep ssh



#===========#
# Variables #
#===========#

# Set bash options to stop script if a command exit with non-zero status
set -e
set -o pipefail

# Options
while [[ $# -gt 0 ]]
do
    case $1 in
        -h1|--host1  ) host1="$2"   ; shift 2 ;;
        -h2|--host2  ) host2="$2"   ; shift 2 ;;
        -b|--browser ) browser="$2" ; shift 2 ;;
        -j|--j_loc   ) j_loc="$2"   ; shift 2 ;;
        -s|--ssha    ) ssha=1       ; shift   ;;
        -p|--sshp    ) sshp=1       ; shift   ;;
        -h|--help    ) usage ; exit 0 ;;
        *            ) error "Invalid option: $1\n$(usage)" 1 ;;
    esac
done


# Default browser
[[ -z "$browser" ]] && browser=firefox

# Test existence of the browser
test_dep "$browser"

# Default Jupyter location
[[ -z "$j_loc" ]] && j_loc="\$HOME/local/bin/jupyter"

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

# List Jupyter servers
mysvr=$($myssh -q -A -o AddKeysToAgent=yes -4 $host1 "ssh $host2 '$j_loc notebook list | tail -n +2 | cut -d \" \" -f 1'")

# Check how many Jupyter servers are running
[[ -z "$mysvr" ]] && error "No server is running. Exiting..." 1
[[ $(echo "$mysvr" | wc -l) -gt 1 ]] && error "More than one server is running. Exiting..." 1

# Identify port and ton
myport_j=$(echo "$mysvr" | cut -d ":" -f 3 | cut -d "/" -f 1)
mytoken_j=$(echo "$mysvr" | cut -d ":" -f 3 | cut -d "/" -f 2)

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

mysocket=/tmp/${USER}_jupyter_socket

# Create tunnel (must deactivate set -e using set +e otherwise script exit)
set +e
$myssh -q -M -S $mysocket -fA -o ServerAliveInterval=60 -L ${myport_l}:localhost:${myport_r} $host1 ssh -4 -L ${myport_r}:localhost:${myport_j} -N $host2

# Identify PID of the tunnel
mypid=$(pgrep -P $$)
mypid=$(echo "$mypid" | tr "\n" " ")

function portk {
    $myssh -q -A $host1 "kill \$(ps ux | grep \"ssh .*-L ${myport_r}:localhost:$1 -N $host2\" | grep -v grep |  sed \"s/  */\t/g\" | cut -f 2)"
}

# Create trap to close ssh tunnel when interrupt
trap "$myssh -q -S $mysocket -O exit $host1 ; portk ${myport_j}" SIGINT SIGTERM

# Reactivate error detection
set -e

# Update server address
#mysvr=$(echo "$mysvr/$mytoken_j/" | sed "s,//*,/,g")

# Start Jupyter page
echo "$mysvr"
info "Starting Firefox tab..."
sleep 2s
firefox "$mysvr" &

# Wait until interruption
info "Once done with Jupyter, use Ctrl-C to close the SSH tunnel..."

sleep inf

# Kill SSH agent if it was started with the script
[[ -n "$sshk" ]] && ssh-agent -k

exit 0
