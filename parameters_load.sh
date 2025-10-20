# --- Load Parameters Function ---
# Loads configuration parameters from parameter.ini file
#
# @uses global PARAMETER_FILE
# @uses global LOG_DIR, SNAPSHOTS, RETENTION_DAYS, CLONE_MP
# @return {integer} 0 for success, 1 for failure.
load_parameters() {
    if [ ! -f "$PARAMETER_FILE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Parameter file '$PARAMETER_FILE' not found." >&2
        return 1
    fi
    
    if [ ! -r "$PARAMETER_FILE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Parameter file '$PARAMETER_FILE' is not readable." >&2
        return 1
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: Reading parameter file..." >&2
    
    # Read parameter file
    while IFS='=' read -r key value; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: Raw line - key='$key' value='$value'" >&2
        
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # Trim whitespace from key
        key=$(echo "$key" | xargs)
        
        # Trim whitespace and remove quotes from value
        value=$(echo "$value" | xargs)
        value="${value%\"}"  # Remove trailing quote
        value="${value#\"}"  # Remove leading quote
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: Processed - key='$key' value='$value'" >&2
        
        case "$key" in
            LOG_DIR)
                LOG_DIR="$value"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: Set LOG_DIR='$LOG_DIR'" >&2
                ;;
            SNAPSHOTS)
                SNAPSHOTS="$value"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: Set SNAPSHOTS='$SNAPSHOTS'" >&2
                ;;
            RETENTION_DAYS)
                RETENTION_DAYS="$value"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: Set RETENTION_DAYS='$RETENTION_DAYS'" >&2
                ;;
            CLONE_MP)
                CLONE_MP="$value"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: Set CLONE_MP='$CLONE_MP'" >&2
                ;;
        esac
    done < "$PARAMETER_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: After parsing - LOG_DIR='$LOG_DIR' SNAPSHOTS='$SNAPSHOTS' RETENTION_DAYS='$RETENTION_DAYS' CLONE_MP='$CLONE_MP'" >&2
    
    # Validate LOG_DIR
    if [ -z "$LOG_DIR" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: LOG_DIR not defined in parameter file." >&2
        return 1
    fi
    
    # Validate LOG_DIR format (should be a directory path)
    if [[ ! "$LOG_DIR" =~ ^/ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: LOG_DIR must be an absolute path starting with '/'. Got: $LOG_DIR" >&2
        return 1
    fi
    
    # Validate SNAPSHOTS
    if [ -z "$SNAPSHOTS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: SNAPSHOTS not defined in parameter file." >&2
        return 1
    fi
    
    if ! [[ "$SNAPSHOTS" =~ ^[0-9]+$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: SNAPSHOTS must be a number. Got: $SNAPSHOTS" >&2
        return 1
    fi
    
    if [ "$SNAPSHOTS" -lt 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: SNAPSHOTS must be greater than or equal to 1. Got: $SNAPSHOTS" >&2
        return 1
    fi
    
    # Validate RETENTION_DAYS
    if [ -z "$RETENTION_DAYS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: RETENTION_DAYS not defined in parameter file." >&2
        return 1
    fi
    
    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: RETENTION_DAYS must be a number. Got: $RETENTION_DAYS" >&2
        return 1
    fi
    
    if [ "$RETENTION_DAYS" -lt 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: RETENTION_DAYS must be greater than or equal to 1. Got: $RETENTION_DAYS" >&2
        return 1
    fi
    
    # Validate CLONE_MP
    if [ -z "$CLONE_MP" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: CLONE_MP not defined in parameter file." >&2
        return 1
    fi
    
    # Validate CLONE_MP format (should be a directory path)
    if [[ ! "$CLONE_MP" =~ ^/ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: CLONE_MP must be an absolute path starting with '/'. Got: $CLONE_MP" >&2
        return 1
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: Parameters loaded successfully:" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') -   LOG_DIR=$LOG_DIR" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') -   SNAPSHOTS=$SNAPSHOTS" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') -   RETENTION_DAYS=$RETENTION_DAYS" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') -   CLONE_MP=$CLONE_MP" >&2
    
    return 0
}