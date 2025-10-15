#!/bin/bash

# Global variables
declare -a current_drive_state
declare -A current_drive_headers
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
    local line_num=0
    
    while IFS= read -r line; do
        if [ $line_num -eq 0 ]; then
            # Parse header row
            local col_num=0
            for header in $line; do
                current_drive_headers[$header]=$col_num
                ((col_num++))
            done
        else
            # Store data rows
            current_drive_state+=("$line")
        fi
        ((line_num++))
    done < "./test-lsblk"
}

# Function to get column value from a row
get_column_value() {
    local row="$1"
    local column_name="$2"
    local col_index="${current_drive_headers[$column_name]}"
    
    echo "$row" | awk -v col=$((col_index + 1)) '{print $col}'
}

# Function to get TRAN type from parent device
get_tran_type() {
    local current_index="$1"
    local current_name=$(get_column_value "${current_drive_state[$current_index]}" "NAME")
    
    # Extract the base device name (e.g., sda from └─sda1)
    # Remove tree characters and partition number
    local base_device=$(echo "$current_name" | sed 's/.*[─├└]//; s/[0-9]*$//' | sed 's/p$//')
    
    debug_print "Current name: $current_name"
    debug_print "Looking for base device: $base_device"
    debug_print "Starting from index: $current_index"
    
    # Search backwards for the parent device
    for ((i=current_index-1; i>=0; i--)); do
        local check_row="${current_drive_state[$i]}"
        local check_name=$(get_column_value "$check_row" "NAME")
        local check_tran=$(get_column_value "$check_row" "TRAN")
        
        debug_print "Checking index $i: name='$check_name' tran='$check_tran'"
        
        # If we find the parent device (no tree characters, matches base name)
        if [[ "$check_name" == "$base_device" ]]; then
            debug_print "Found parent device!"
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
    
    # Get TRAN from parent device
    local tran=$(get_tran_type "$row_index")
    
    # Strip tree characters and extract device name
    local stripped_partition=$(echo "$name" | sed 's/.*[─├└]//')
    
    # Prepend /dev/ if it's a device partition
    if [[ "$stripped_partition" =~ ^(sd[a-z][0-9]+|nvme[0-9]+n[0-9]+p[0-9]+) ]]; then
        stripped_partition="/dev/$stripped_partition"
    fi
    
    echo "  Drive location: $stripped_partition"
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
        
        # Check if label is UNRAID and name ends in 1
        if [[ "$label" == "UNRAID" ]] && [[ "$name" =~ 1$ ]]; then
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