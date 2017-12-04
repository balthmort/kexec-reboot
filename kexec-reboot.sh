#!/bin/env bash
# Author: Petr "Mort" Surý
# File: kexec-reboot.sh


# Auxiliary functions
#
# Colorized output of echo - you know, if it's fancy, it's good
# first param - color
# second param - text
cecho() { # {{{
  local code="\033["
  case "$1" in
    black  | bk) color="${code}0;30m";;
    red    |  r) color="${code}1;31m";;
    green  |  g) color="${code}1;32m";;
    yellow |  y) color="${code}1;33m";;
    blue   |  b) color="${code}1;34m";; 
    purple |  p) color="${code}1;35m";;
    cyan   |  c) color="${code}1;36m";;
    gray   | gr) color="${code}0;37m";;
    *) local text="$1"
  esac
  [ -z "$text" ] && local text="$color$2${code}0m"
  echo -e "$text"
} # }}}

# Usage
usage() { # {{{
  cecho c "-------------------------------------------"
  cat << EOF
Usage: kexec-reboot [option...] 
You must be superuser to use this program!
Shows interactive menu for kexec reboot
Options are:
  --help,         -h - show this help message
  --interactive,  -i - reboot kernel interactively
  --present,      -p - reboot into present kernel, default
EOF
  cecho c "-------------------------------------------"
  exit "$1"
} # }}}

# Error reporting 
err (){ # {{{
  cecho r "Error: $1" >&2
  usage 1
} # }}}

# ------------------------------------------------------------------------------
# Main program
# only root can read grub.cfg {{{
(( UID != 0 )) && err "You need to be superuser" # }}}

# Option parsing # {{{
invalid_options=()
h_flag=false
i_flag=false
p_flag=false
while true; do
  case $1 in 
    -h | --help)
      h_flag=true
      shift;;
    -i | --interactive)
      i_flag=true
      shift;;
    -p | --present)
      p_flag=true
      shift;;
    --)
      shift
      break;;
    *)
      if [ -z "$1" ]; then 
        break
      else 
        invalid_options+=("$1")
        shift
      fi;;
  esac
done 

# The right side of && will only be evaluated if the exit status of the left
# side is zero. || is the opposite: it will evaluate the right side only if the
# left side exit status is nonzero. 

# Print invalid options, help message and exit
[ ! -z "$invalid_options" ] && err "Invalid options: ${invalid_options[*]}"
# Print help and exit
$h_flag && usage 0
# Ensure that there is only one of interactive or present modes
#xor $i_flag $p_flag && err "Only one of modes (non/interactive) can be set."
! ($i_flag && $p_flag) || err "Only one or none of modes (non/interactive) can be set."
# }}}

# Everything we hnow, we know from grub.cfg. All hail our dark lord!TODO: set
# correct grub.cfg {{{
if [ -e /boot/grub2/grub.cfg ];then
  grub_cfg=/boot/grub2/grub.cfg
elif [ -e /boot/grub2.cfg ];then
  grub_cfg=/boot/grub2.cfg
elif [ -e /boot/efi/EFI/centos/grub.cfg ];then
  grub_cfg=/boot/efi/EFI/centos/grub.cfg
else
  err "Cannout find grub.cfg"
fi # }}}

# Prepare menu and correct params
# Parse grub.cfg {{{
oldIFS=$IFS
IFS=$'\n'

menu_entries=($(awk 'BEGIN {KERNEL_VERSION="";                                    # set variables to empty string
            VMLINUX="";
            KERNEL_ARGS="";
            INITRD=""
            }
    /menuentry.*+{/,/}/ {                                                         # range from "menuentry ..." to "}"
    if ($0 ~ /menuentry/) {
      for(i=1;i<=NF;++i) {if ($i ~ /\(.*+\)/) 
        {KERNEL_VERSION=KERNEL_VERSION substr($i,2,length($i)-2) "|"; break}};}   # set kernel version
        if ($1 ~ /linux(16|efi)/) {VMLINUX=VMLINUX $2 "|";                        # set kernel to boot
      ORS=" "; TMP_ARGS=""; for(i=3;i<=NF;++i) TMP_ARGS=TMP_ARGS " " $i;
      KERNEL_ARGS=KERNEL_ARGS substr(TMP_ARGS,2,length(TMP_ARGS)-1) "|"; ORS=""}; # set kernel arguments
    if ($1 ~ /initrd(16|efi)/) {ORS="\n"; INITRD=INITRD $2 "|"};                  # set initrd
    }
    END {print KERNEL_VERSION "\n" VMLINUX "\n" KERNEL_ARGS "\n" INITRD}          # print variables
    ' $grub_cfg)) 

IFS=$oldIFS # }}}

# split parsed grub.cfg into individual arrays {{{
oldIFS=$IFS
IFS="|"
kernel=(${menu_entries[0]})
vmlinux=(${menu_entries[1]})
args=(${menu_entries[2]})
initrd=(${menu_entries[3]})
IFS=$oldIFS # }}}

# Load kernel + some confirmations
load_and_ask(){ # {{{
  cecho y "Loading kernel ${kernel[$1]}"
  echo kexec -l "/boot${vmlinux[$1]}" --append="${args[$1]}" --initrd="/boot${initrd[$1]}"
  kexec -l "/boot${vmlinux[$1]}" --append="${args[$1]}" --initrd="/boot${initrd[$1]}"
  if [ $? -eq 0 ]; then
    cecho g "Kernel loaded"
  else
    err "Unknown error while loading kernel"
  fi 
  cecho y "Do you want to reboot now? [y/n] \c"; read -r choice
  if [[ $choice == "y" ]]; then
    kexec -e
  elif [[ $choice == "n" ]]; then
    cecho r "Aborting reboot! Unloading kernel"
    kexec -u
  else
    err "Wrong option, aborting reboot, unloading kernel"
    kexec -u 
  fi
}
# }}}

# According to chosen mode start in non/interactive mode {{{
if $i_flag; then
  cecho y "Interactive mode"
  for (( i=0; i<${#kernel[@]}; i++ )); do
    cecho c "$i: \c";cecho gr "${kernel[$i]}"
  done
  cecho g "Please choose kernel: \c"; read -r choice
  # Make sure the selected number is an integer
  [[ $choice == *[^0-9]* ]] && err "The selected parameter is not a number"
  [[ $choice -gt ${#kernel[@]}-1 ]] && err "You cannot choose param greater than number of kernels"
  cecho p "You have chosen wisely"
  load_and_ask "$choice"
else
  cecho y "Non interactive mode"
  load_and_ask 0
fi # }}}
