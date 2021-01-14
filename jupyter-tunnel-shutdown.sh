#!/bin/bash
# Title: jupyter-tunnel-shutdown.sh
# Version: 0.0
# Author: Frédéric CHEVALIER <fcheval@txbiomed.org>
# Created in: 2021-01-15
# Modified in:
# Licence : GPL v3



#======#
# Aims #
#======#

aim="Send an interruption signal to any jupyter-tunnel processes. This is the equivalent of Ctrl+C."



#==========#
# Versions #
#==========#

# v0.0 - 2021-01-15: creation

version=$(grep -i -m 1 "version" "$0" | cut -d ":" -f 2 | sed "s/^ *//g")



#===========#
# Functions #
#===========#

# Usage message
function usage {
    echo -e "
    \e[32m ${0##*/} \e[00m -h|--help

Aim: $aim

Version: $version

Options:
    -h, --help      this message
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



#===========#
# Variables #
#===========#

# Options
while [[ $# -gt 0 ]]
do
    case $1 in
        -h|--help   ) usage ; exit 0 ;;
        *           ) error "Invalid option: $1\n$(usage)" 1 ;;
    esac
done



#============#
# Processing #
#============#

# List PID of tunnel(s)
mytunnels=$(pgrep -f "jupyter-tunnel\.sh")

# Test if there is any tunnel
[[ -z $mytunnels ]] && info "No tunnel to kill. Exiting..." && exit 0


# Kill all tunnel
for i in $mytunnels
do
    kill -2 -$i
    wait
	info "Killed process $i"
done

exit 0
