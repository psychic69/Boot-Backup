#!/bin/bash

# Global variables
declare -a current_drive_state
DEBUG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -debug)
            DEBUG=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-debug]"
            exit 1
            ;;
    esac
done

# Debug print function
debug_print() {
    if [ "$DEBUG" = true ]; then
        echo "DEBUG: $*" >&2
    fi
}

# Function to load the lsblk data
load_drive_state() {
    while IFS= read -r line; do
        current_drive_state+=("$line")
    done < "./test-lsblk"
}

# Function to get column value from a key=value pair line
get_column_value() {
    local row="$1"
    local column_name="$2"
    
    # Extract value using parameter expansion
    local pattern="${column_name}=\"([^\"]*)\""
    if [[ $row =~ $pattern ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Function to get TRAN type from parent device
get_tran_type() {
    local current_index="$1"
    local current_name=$(get_column_value "${current_drive_state[$current_index]}" "NAME")
    
    # Extract the base device name (e.g., sda from sda1, nvme0n1 from nvme0n1p1)
    local base_device=$(echo "$current_name" | sed 's/[0-9]*$//' | sed 's/p$//')
    
    debug_print "Current name: $current_name"
    debug_print "Looking for base device: $base_device"
    debug_print "Starting from index: $current_index"
    
    # Search backwards for the parent device
    for ((i=current_index-1; i>=0; i--)); do
        local check_row="${current_drive_state[$i]}"
        local check_name=$(get_column_value "$check_row" "NAME")
        local check_tran=$(get_column_value "$check_row" "TRAN")
        
        debug_print "Checking index $i: name='$check_name' tran='$check_tran'"
        
        # If we find the parent device (matches base name)
        if [[ "$check_name" == "$base_device" ]]; then
            debug_print "Found parent device with TRAN='$check_tran'"
            echo "$check_tran"
            return
        fi
    done
    
    debug_print "No parent device found"
    echo ""
}

# Function to print partition state
print_partition_state() {
    local row="$1"
    local row_index="$2"
    
    local name=$(get_column_value "$row" "NAME")
    local mountpoint=$(get_column_value "$row" "MOUNTPOINT")
    local uuid=$(get_column_value "$row" "UUID")
    local fstype=$(get_column_value "$row" "FSTYPE")
    local label=$(get_column_value "$row" "LABEL")
    local size=$(get_column_value "$row" "SIZE")
    local tran=$(get_column_value "$row" "TRAN")
    
    # If TRAN is empty, get it from parent device
    if [[ -z "$tran" ]]; then
        tran=$(get_tran_type "$row_index")
    fi
    
    # Prepend /dev/ if it's a device partition
    local drive_location="$name"
    if [[ "$name" =~ ^(sd[a-z][0-9]+|nvme[0-9]+n[0-9]+p[0-9]+|md[0-9]+p[0-9]+) ]]; then
        drive_location="/dev/$name"
    fi
    
    echo "  Drive location: $drive_location"
    echo "  Current Mountpoint: $mountpoint"
    echo "  UUID: $uuid"
    echo "  File type: $fstype"
    echo "  Current Label: $label"
    echo "  Drive Size: $size"
    echo "  Transport Type: $tran"
    echo ""
}

# Main function
initial_test() {
    # Load the drive state
    load_drive_state
    
    # Find all partitions with LABEL "UNRAID" where NAME ends in "1"
    local -a unraid_partitions
    local -a unraid_indices
    
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local label=$(get_column_value "$row" "LABEL")
        local name=$(get_column_value "$row" "NAME")
        
        debug_print "Checking row $i: name='$name' label='$label'"
        
        # Check if label is UNRAID and name ends in 1
        if [[ "$label" == "UNRAID" ]] && [[ "$name" =~ 1$ ]]; then
            debug_print "Found UNRAID partition: $name"
            unraid_partitions+=("$row")
            unraid_indices+=("$i")
        fi
    done
    
    # Check if we have exactly one UNRAID partition
    if [ ${#unraid_partitions[@]} -ne 1 ]; then
        echo "Error: You have multiple partitions with the label: UNRAID. You must only have one or the system may not boot properly. Please resolve"
        echo ""
        
        for idx in "${!unraid_partitions[@]}"; do
            print_partition_state "${unraid_partitions[$idx]}" "${unraid_indices[$idx]}"
        done
        
        exit 1
    fi
    
    # We have exactly one UNRAID partition
    echo "The current booted environment is as follows"
    echo ""
    print_partition_state "${unraid_partitions[0]}" "${unraid_indices[0]}"
}

# Run the main function
initial_test