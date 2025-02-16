#!/bin/bash

# This script is intended to run on a Lambda machine and collects various system logs and information for diagnostic purposes.
# It includes the use of NVIDIA's bug report script to gather detailed information about NVIDIA GPUs and other system info.
# Credit to NVIDIA Corporation for the nvidia-bug-report.sh script.
# Note: This script consolidates system information, which may include sensitive data. User discretion advised.

# Copyright 2024 Lambda, Inc.
# Website:		https://lambdalabs.com
# Author(s):		Bryan Gwin, Ryan England
# Script License:	BSD 3-clause

# Script info and disclaimer
script_info_and_disclaimer() {
    echo "This script is intended to run on a Lambda machine and collects various system logs and information for diagnostic purposes."
    echo "It includes the use of NVIDIA's bug report script to gather detailed information about NVIDIA GPUs and other system info."
    echo "Credit to NVIDIA Corporation for the nvidia-bug-report.sh script."
    echo
    echo "This script will, optionally, attempt to install any missing packages required for collecting system information."
    echo "This script may install the following:"
    CURRENT_TOOL=0
    while [ ${CURRENT_TOOL} -lt ${#NEEDED_TOOLS[@]} ]; do
        set -- $(echo ${NEEDED_TOOLS[${CURRENT_TOOL}]} | tr -d ',')
        echo " * ${2}"
        CURRENT_TOOL=$((${CURRENT_TOOL}+1))
    done
    echo
    echo "By delivering 'lambda-bug-report.log.gz' to Lambda, you acknowledge"
    echo "and agree that sensitive information may inadvertently be included in"
    echo "the output. Notwithstanding the foregoing, Lambda will use the"
    echo "output only for the purpose of investigating your reported issue."
    echo
}

# We will later check whether this machine will benefit from certain tools, rather than just installing them.
# Proactively assume the machine is not a VM
IS_VIRTUAL_MACHINE=0

check_if_virtualized() {
    SYSTEM_MANUFACTURER="$(sudo dmidecode | grep -A1 "System Information" | grep "Manufacturer" | sed 's/^\tManufacturer: //')"
    if [[ "${SYSTEM_MANUFACTURER}" == "QEMU" ]]; then
        IS_VIRTUAL_MACHINE=1
    else
        IS_VIRTUAL_MACHINE=0
    fi
}

# List the tools to install and any tool metadata
# Usage:
#     executable to check for,
#     package name,
#     tool is useful for VMs (0 = no, 1 = yes)
declare -a NEEDED_TOOLS
NEEDED_TOOLS=(
    "smartmonctl, smartmontools, 0",
    "ipmitool, ipmitool, 0",
    "sensors, lm-sensors, 0",
    "iostat, sysstat, 1",
    "lshw, lshw, 1"
)

# By default, do not install tools.
SKIP_TOOLS=${SKIP_TOOLS:-1}

install_needed_tools() {
    if [ $SKIP_TOOLS -eq 1 ]; then
        # The script has been told not to install tools, no need to proceed further with this fuction.
        return
    fi

    sudo apt-get update >/dev/null 2>&1

    CURRENT_TOOL=0
    while [ ${CURRENT_TOOL} -lt ${#NEEDED_TOOLS[@]} ]; do
        # Bash does not have multidimensional arrays, but it's possible to make do in a way that is reasonably easy to read.
        set -- $(echo ${NEEDED_TOOLS[${CURRENT_TOOL}]} | tr -d ',')

        # Proactively assume a tool is not beneficial on a VM
        IS_VM_TOOL=${3:-0}

        if [[ $IS_VIRTUAL_MACHINE -eq 1 && $IS_VM_TOOL -eq 0 ]]; then
            # The tool is not beneficial for a VM, no need to proceed further with this iteration of the loop.
            CURRENT_TOOL=$((${CURRENT_TOOL}+1))
            continue
        fi

        if command -v ${1} >/dev/null 2>&1; then
            # The tool is already available, no need to proceed further with this iteration of the loop.
            CURRENT_TOOL=$((${CURRENT_TOOL}+1))
            continue
        fi

        echo Installing ${2}
        sudo apt-get install -y ${2} >/dev/null 2>&1

        CURRENT_TOOL=$((${CURRENT_TOOL}+1))
    done
}

script_info_and_disclaimer

check_if_virtualized

install_needed_tools

# Define and create temporary directory
TMP_DIR="tmp_lambda_bug_report"
mkdir -p "$TMP_DIR"

# Define and create main directory for logs
FINAL_DIR="$TMP_DIR/lambda-bug-report"
mkdir -p "$FINAL_DIR"

# Directories under lambda-bug-report
DRIVES_AND_STORAGE_DIR="$FINAL_DIR/drives-and-storage"
mkdir -p "$DRIVES_AND_STORAGE_DIR"
SYSTEM_LOGS_DIR="$FINAL_DIR/system-logs"
mkdir -p "$SYSTEM_LOGS_DIR"
REPOS_AND_PACKAGES_DIR="$FINAL_DIR/repos-and-packages"
mkdir -p "$REPOS_AND_PACKAGES_DIR"
NETWORKING_DIR="$FINAL_DIR/networking"
mkdir -p "$NETWORKING_DIR"
GPU_MEMORY_ERRORS_DIR="$FINAL_DIR/gpu-memory-errors"
mkdir -p "$GPU_MEMORY_ERRORS_DIR"
BMC_INFO_DIR="$FINAL_DIR/bmc-info"
mkdir -p "$BMC_INFO_DIR"
GRUB_DIR="$FINAL_DIR/grub"
mkdir -p "$GRUB_DIR"

# Collect SMART data for all drives
collect_drive_checks() {
    lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,FSTYPE,LABEL,UUID,TYPE,MOUNTPOINT >"$DRIVES_AND_STORAGE_DIR/lsblk.txt"

    # Collect SMART data for all drives
    DRIVES=$(lsblk | egrep "^sd|^nvm" | awk '{print $1}')
    for DRIVE in ${DRIVES}; do
        sudo smartctl -x /dev/"${DRIVE}" >"$DRIVES_AND_STORAGE_DIR/smartctl-${DRIVE}.txt" 2>&1
    done
}

# Generate NVIDIA bug report
echo "Running nvidia-bug-report.sh..."
sudo nvidia-bug-report.sh >/dev/null 2>&1

# If nvidia-bug-report.log.gz exists, decompress it
if [ -f "nvidia-bug-report.log.gz" ]; then
    gunzip -c nvidia-bug-report.log.gz >"${FINAL_DIR}/nvidia-bug-report.log"
    sudo rm nvidia-bug-report.log.gz
fi

echo "Collecting system logs and information..."

# Collect system logs
for log in /var/log/dmesg /var/log/kern.log /var/log/syslog /var/log/dpkg.log; do
    if [ -f "$log" ]; then
        sudo cp "$log" "$SYSTEM_LOGS_DIR/"
    fi
done

# Collect all apt history logs into one sorted file
find /var/log/apt -type f -name "history.log*" | sort -Vr | while read log; do
    if [[ "$log" =~ \.gz$ ]]; then
        zcat "$log" | sudo tee -a "$SYSTEM_LOGS_DIR/apt-history.log" >/dev/null
    else
        cat "$log" | sudo tee -a "$SYSTEM_LOGS_DIR/apt-history.log" >/dev/null
    fi
done

sudo dmesg -Tl err >"${SYSTEM_LOGS_DIR}/dmesg-errors.txt"
sudo journalctl >"${SYSTEM_LOGS_DIR}/journalctl.txt"

ibstat >"${FINAL_DIR}/ibstat.txt" 2>/dev/null
if [ ! -s "${FINAL_DIR}/ibstat.txt" ]; then
    echo "No InfiniBand data available. This machine may not have InfiniBand." >"${FINAL_DIR}/ibstat.txt"
fi

sudo ipmitool sel elist >"${BMC_INFO_DIR}/ipmi-elist.txt" 2>/dev/null
if [ ! -s "${BMC_INFO_DIR}/ipmi-elist.txt" ]; then
    echo "No IPMI ELIST data available. This machine may not have IPMI." >"${BMC_INFO_DIR}/ipmi-elist.txt"
fi
sudo ipmitool sdr >"${BMC_INFO_DIR}/ipmi-sdr.txt" 2>/dev/null
if [ ! -s "${BMC_INFO_DIR}/ipmi-sdr.txt" ]; then
    echo "No IPMI SDR data available. This machine may not have IPMI." >"${BMC_INFO_DIR}/ipmi-sdr.txt"
fi

sensors >"${FINAL_DIR}/sensors.txt" 2>/dev/null
if [ ! -s "${FINAL_DIR}/sensors.txt" ]; then
    echo "No sensor data available. This machine may not have sensors." >"${FINAL_DIR}/sensors.txt"
fi

sudo iostat -xt >"${DRIVES_AND_STORAGE_DIR}/iostat.txt" 2>/dev/null
if [ ! -s "${DRIVES_AND_STORAGE_DIR}/iostat.txt" ]; then
    echo "No iostat data available. This machine may not have iostat." >"${DRIVES_AND_STORAGE_DIR}/iostat.txt"
fi

sudo lshw >"${FINAL_DIR}/hw-list.txt" 2>/dev/null
if [ ! -s "${FINAL_DIR}/hw-list.txt" ]; then
    echo "No lshw data available. This machine may not have lshw." >"${FINAL_DIR}/hw-list.txt"
fi

# Collect SW Raid info
if command -v mdadm >/dev/null 2>&1; then
    sudo mdadm --detail --scan >"${DRIVES_AND_STORAGE_DIR}/mdadm-scan.txt"
    cat /etc/mdadm/mdadm.conf >"${DRIVES_AND_STORAGE_DIR}/mdadm-conf.txt"
fi

# Collecdt GRUB info
cat /proc/cmdline >"${GRUB_DIR}/proc_cmdline.txt"
cat /etc/default/grub >"${GRUB_DIR}/grub.txt"
if [ -d /etc/default/grub.d/ ]; then
    cp -r /etc/default/grub.d/ "${GRUB_DIR}/"
fi

# Check for memory remapping and memory errors on GPUs
nvidia-smi --query-remapped-rows=gpu_bus_id,gpu_uuid,remapped_rows.correctable,remapped_rows.uncorrectable,remapped_rows.pending,remapped_rows.failure \
    --format=csv >"${GPU_MEMORY_ERRORS_DIR}/remapped-memory.txt" 2>&1
if [ ! -s "${GPU_MEMORY_ERRORS_DIR}/remapped-memory.txt" ]; then
    echo "No nvidia-smi data available. This machine may not have nvidia-smi." >"${GPU_MEMORY_ERRORS_DIR}/remapped-memory.txt"
fi

nvidia-smi --query-gpu=index,pci.bus_id,uuid,ecc.errors.corrected.volatile.dram,ecc.errors.corrected.volatile.sram \
    --format=csv >"${GPU_MEMORY_ERRORS_DIR}/ecc-errors.txt" 2>&1
if [ ! -s "${GPU_MEMORY_ERRORS_DIR}/ecc-errors.txt" ]; then
    echo "No nvidia-smi data available. This machine may not have nvidia-smi." >"${GPU_MEMORY_ERRORS_DIR}/ecc-errors.txt"
fi

nvidia-smi --query-gpu=index,pci.bus_id,uuid,ecc.errors.uncorrected.aggregate.dram,ecc.errors.uncorrected.aggregate.sram \
    --format=csv >"${GPU_MEMORY_ERRORS_DIR}/uncorrected-ecc_errors.txt" 2>&1
if [ ! -s "${GPU_MEMORY_ERRORS_DIR}/uncorrected-ecc_errors.txt" ]; then
    echo "No nvidia-smi data available. This machine may not have nvidia-smi." >"${GPU_MEMORY_ERRORS_DIR}/uncorrected-ecc_errors.txt"
fi

# Check hibernation settings
sudo systemctl status hibernate.target hybrid-sleep.target \
    suspend-then-hibernate.target sleep.target suspend.target >"${FINAL_DIR}/hibernation-settings.txt"

# Collect sources.list.d repo info
output_file="${REPOS_AND_PACKAGES_DIR}/listd-repos.txt"

for file in /etc/apt/sources.list.d/*; do
    if [ -f "$file" ]; then
        echo "$(basename "$file")" >>"$output_file"

        cat "$file" >>"$output_file"

        echo "" >>"$output_file"
    fi
done

# Collect other system information
df -hTP >"${DRIVES_AND_STORAGE_DIR}/df.txt"
cat /etc/fstab >"${DRIVES_AND_STORAGE_DIR}/fstab.txt"
cat /proc/mdstat >"${DRIVES_AND_STORAGE_DIR}/mdstat.txt"
lsmod >"${FINAL_DIR}/lsmod.txt"
dpkg -l >"${REPOS_AND_PACKAGES_DIR}/dpkg.txt"
export PIP_DISABLE_PIP_VERSION_CHECK=1
pip -v list >"${REPOS_AND_PACKAGES_DIR}/pip-list.txt" 2>/dev/null
unset PIP_DISABLE_PIP_VERSION_CHECK
grep -v '^#' /etc/apt/sources.list >"${REPOS_AND_PACKAGES_DIR}/sources-list.txt"
cat /proc/mounts >"${DRIVES_AND_STORAGE_DIR}/mounts.txt"
sudo sysctl -a >"${FINAL_DIR}/sysctl-all.txt"
systemctl --type=service >"${FINAL_DIR}/systemctl-services.txt"
sudo netplan get all >"${NETWORKING_DIR}/netplan.txt" 2>/dev/null
ip addr >"${NETWORKING_DIR}/ip-addr.txt"
sudo iptables -L --line-numbers >"${NETWORKING_DIR}/iptables.txt"
sudo ufw status >"${NETWORKING_DIR}/ufw-status.txt"
sudo resolvectl status >"${NETWORKING_DIR}/resolvectl-status.txt"
top -n 1 -b >"${FINAL_DIR}/top.txt"
nvidia-smi >"${FINAL_DIR}/nvidia-smi.txt" 2>&1
if [ ! -s "${FINAL_DIR}/nvidia-smi.txt" ]; then
    echo "No nvidia-smi data available. This machine may not have nvidia-smi." >"${FINAL_DIR}/nvidia-smi.txt"
fi
nvidia-smi -q | grep -E "Serial Number|Bus Id" >"${FINAL_DIR}/gpu-serials.txt" 2>&1
if [ ! -s "${FINAL_DIR}/gpu-serials.txt" ]; then
    echo "No nvidia-smi data available. This machine may not have nvidia-smi." >"${FINAL_DIR}/gpu-serials.txt"
fi
sudo ss --tcp --udp --listening --numeric --process >"${NETWORKING_DIR}/ss.txt"
echo "$(uptime -p)" since "$(uptime -s)" >"${FINAL_DIR}/uptime.txt"

collect_drive_checks

# Compress all collected logs into a single file
sudo tar -zcf lambda-bug-report.tar.gz -C "$TMP_DIR" lambda-bug-report

# Cleanup
rm -rf "$TMP_DIR"

echo
echo "All logs have been collected and compressed into lambda-bug-report.tar.gz."
echo
