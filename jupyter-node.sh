#!/bin/bash
# Title: jupyter-node.sh
# Version: 0.0
# Author: Frédéric CHEVALIER <fcheval@txbiomed.org>
# Created in: 2021-05-21
# Modified in:
# Licence : GPL v3



#======#
# Aims #
#======#

aim="Start Jupyter server on a node of a SGE cluster from the head node."

# source: https://gist.github.com/martijnvermaat/6357551



#==========#
# Versions #
#==========#

# v0.0 - 2021-05-21: creation

version=$(grep -i -m 1 "version" "$0" | cut -d ":" -f 2 | sed "s/^ *//g")



#===========#
# Functions #
#===========#

# Usage message
function usage {
    echo -e "
    \e[32m ${0##*/} \e[00m -q|--queue value -n|--node value -l|--log path -h|--help

Aim: $aim

Version: $version

Options:
    -q, --queue     queue name
    -n, --node      host / node name
    -l, --log       path to log file (default: /tmp/jupyter_nb_${USER}_$(hostname)_XXXXXXX.log)
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


# Clean up function for trap command
## Usage: clean_up file1 file2 ...
function clean_up {
    rm -rf $@
    exit 1
}



#==============#
# Dependencies #
#==============#

test_dep qrsh
test_dep jupyter



#===========#
# Variables #
#===========#

# Options
while [[ $# -gt 0 ]]
do
    case $1 in
        -q|--queue  ) myq="$2" ; shift 2 ;;
        -n|--node   ) myn="$2" ; shift 2 ;;
        -l|--log    ) mylog="$2" ; shift 2 ;;
        -h|--help   ) usage ; exit 0 ;;
        *           ) error "Invalid option: $1\n$(usage)" 1 ;;
    esac
done

# Updating variables
[[ -n "$myq" ]] && myq="-l q=$myq"
[[ -n "$myn" ]] && myn="-l h=$myn"

# Log default option
[[ -z "$mylog" ]] && mylog="$(mktemp -t jupyter_nb_${USER}_$(hostname)_XXXXXXX.log)"
chmod 600 "$mylog"



#============#
# Processing #
#============#

# Starting notebook
qrsh -V -N notebook $myq $myn \
    jupyter notebook \
        --config="$HOME/.jupyter/jupyter_notebook_config.py" \
        --no-browser \
        --ip=\$\(hostname --fqdn\) &> "$mylog" &

exit 0
