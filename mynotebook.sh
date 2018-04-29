#!/bin/bash
# Title: mynotebook.sh
# Version: 0.1
# Author: Frédéric CHEVALIER <fcheval@txbiomed.org>
# Created in: 2017-11-05
# Modified in: 2018-04-29
# Licence : GPL v3



#======#
# Aims #
#======#

aim="Create a SSH tunnel to connect to Jupyter notebook server running remotely and start the internet browser."



#==========#
# Versions #
#==========#

# v0.1 - 2018-04-29: use of a socket for SSH tunnel
# v0.0 - 2017-11-05: creation

version=$(grep -i -m 1 "version" "$0" | cut -d ":" -f 2 | sed "s/^ *//g")



#===========#
# Functions #
#===========#

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



#===========#
# Variables #
#===========#

host1=$1
host2=$2


#============#
# Processing #
#============#

mysvr=$(ssh -A $host1 "ssh $host2 '/master/fcheval/local/bin/jupyter notebook list | tail -n +2 | cut -d \" \" -f 1'")

# Check how many Jupyter servers are running
[[ -z "$mysvr" ]] && error "No server is running. Exiting..." 1
[[ $(echo "$mysvr" | wc -l) -gt 1 ]] && error "More than one server is running. Exiting..." 1

# Identify port and token
myport_j=$(echo "$mysvr" | cut -d ":" -f 3 | cut -d "/" -f 1)
#mytoken_j=$(echo "$mysvr" | cut -d ":" -f 3 | cut -d "/" -f 2)

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
port_list=$(ssh -A $host1 'netstat -ant | tail -n +3 | sed "s/  */\t/g" | cut -f 4 | cut -d ":" -f 2 | sort | uniq')
for ((i=9999 ; i <= 40000 ; i++))
do
    [[ $(echo "$port_list" | grep -w $i) ]] || break
done

myport_r=$i
info "Port used for the SSH tunnel on $host1: $myport_r"

mysocket=/tmp/${USER}_jupyter_socket

# Create tunnel
ssh -M -S $mysocket -fA -o ServerAliveInterval=600 -L ${myport_l}:localhost:${myport_r} $host1 ssh -L ${myport_r}:localhost:${myport_j} -N $host2 

# Identify PID of the tunnel
mypid=$(pgrep -P $$)
mypid=$(echo "$mypid" | tr "\n" " ")

function portk {
    ssh -A $host1 "kill \$(ps ux | grep \"ssh -L ${myport_r}:localhost:$1 -N $host2\" | grep -v grep |  sed \"s/  */\t/g\" | cut -f 2)"
}

echo $mypid
# Create trap to close ssh tunnel when interrupt
trap "ssh -S $mysocket -O exit $host1 ; portk ${myport_j}" SIGINT SIGTERM

# Start Jupyter page
echo "$mysvr"
info "Starting Firefox tab..."
sleep 2s
firefox "$mysvr" &

# Wait until interruption
info "Once done with Jupyter, use Ctrl-C to close the SSH tunnel..."

sleep inf

exit 0
