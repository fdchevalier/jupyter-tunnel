#!/bin/bash
# Title: jupyter-node.sh
# Version: 0.2
# Author: Frédéric CHEVALIER <fcheval@txbiomed.org>
# Created in: 2021-05-21
# Modified in: 2021-11-24
# Licence : GPL v3



#======#
# Aims #
#======#

aim="Start Jupyter server on a node of a SGE cluster from the head node."

# source: https://gist.github.com/martijnvermaat/6357551



#==========#
# Versions #
#==========#

# v0.2 - 2021-11-24: check status of submission
# v0.1 - 2021-07-30: add option to choose between notebook and lab server / add info message
# v0.0 - 2021-05-21: creation

version=$(grep -i -m 1 "version" "$0" | cut -d ":" -f 2 | sed "s/^ *//g")



#===========#
# Functions #
#===========#

# Usage message
function usage {
    echo -e "
    \e[32m ${0##*/} \e[00m -q|--queue value -n|--node value -l|--log path -t|--type value -w|--wait value -h|--help

Aim: $aim

Version: $version

Options:
    -q, --queue     queue name
    -n, --node      host / node name
    -l, --log       path to log file [default: /tmp/jupyter_nb_${USER}_$(hostname)_XXXXXXX.log]
    -t, --type      server type. Two value possible:
                        * notebook [default]
                        * lab
    -w, --wait      waiting time before checking submission status [default: 15s]
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
        -q|--queue  ) myq="$2"    ; shift 2 ;;
        -n|--node   ) myn="$2"    ; shift 2 ;;
        -l|--log    ) mylog="$2"  ; shift 2 ;;
        -t|--type   ) mytype="$2" ; shift 2 ;;
        -w|--wait   ) mytime="$2" ; shift 2 ;;
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

# Waiting time (must be compatible with sleep)
[[ -z "$mytime" ]] && mytime=15s
[[ ! $(egrep -w "^[[:digit:]]+(\.[[:digit:]]+)?[dhms]?$" <<< "$mytime") ]] && error "Waiting time must follow sleep command syntax. Exiting..." 1

# Jupyter server type
[[ -n "$mytype" && ! "$mytype" =~ ^(notebook|lab)$ ]] && error "Type must be notebook or lab. Exiting..." 1
[[ -z "$mytype" || "$mytype" == notebook ]] && mytype="notebook" && job_name="notebook"
[[ "$mytype" == lab ]] && mytype="lab" && job_name="jp-lab"



#============#
# Processing #
#============#

# Starting notebook
(qrsh -V -N $job_name $myq $myn \
    jupyter $mytype \
        --config="$HOME/.jupyter/jupyter_notebook_config.py" \
        --no-browser \
        --ip=\$\(hostname --fqdn\) &> "$mylog") &

# qrsh PID
mypid=$!

info "Jupyter $mytype has been submitted to the queue."

# Check submission
if [[ ! $mytime =~ ^0+[dhms]?$ ]]
then

    # Pause
    info "Waiting $mytime before checking submission..."
    sleep "$mytime"

    # Check if qrsh still exists
    if [[ ! $(ps -p $mypid -o pid=) ]]
    then
        # Wait for qrsh to exit
        wait $mypid

        # Check qrsh exit status 
        mystatus=$?
        [[ $mystatus != 0 ]] && error "An error occurred during job submission. See log $mylog for more information. Exiting..." 1
    else
        info  "Submitted job is still running." 
    fi
    
fi

exit 0
