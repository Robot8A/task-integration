#!/bin/bash

# This script executes steps 8 to 10 of the HOTOSM data processing pipeline in a loop until all projects are processed.

# Ensure the config.py file exists
if [ ! -f "config.py" ]; then
    echo "config.py file not found. Please ensure it exists in the current directory."
    exit 1
fi

# Extract PostgreSQL parameters from config.py
host=$(grep -oP "database_host\s*=\s*['\"]\K[^'\"]+" config.py)
port=$(grep -oP "database_port\s*=\s*['\"]\K[^'\"]+" config.py)
database=$(grep -oP "database_name\s*=\s*['\"]\K[^'\"]+" config.py)
user=$(grep -oP "database_user\s*=\s*['\"]\K[^'\"]+" config.py)
export PGPASSWORD=$(grep -oP "database_password\s*=\s*['\"]\K[^'\"]+" config.py)

loop_count=0
cont_finished=false
dup_finished=false

while true; do

    echo "********************************"
    echo "Loop count: $loop_count"

    # 08A
    echo "$(date) | EXECUTING SQL SCRIPT 08A_cont_dup_populate_mockup_grids.sql..."
    psql -h $host -p $port -d $database -U $user -f ./08A_cont_dup_populate_mockup_grids.sql

    # 09A
    echo "$(date) | EXECUTING SQL SCRIPT 09A_cont_dup_nonconnecting_nodes.sql..."
    psql -h $host -p $port -d $database -U $user -f ./09A_cont_dup_nonconnecting_nodes.sql

    # 09B
    echo "$(date) | EXECUTING SQL SCRIPT 09B_cont_dup_duplicated_buildings.sql..."
    psql -h $host -p $port -d $database -U $user -f ./09B_cont_dup_duplicated_buildings.sql

    # 10A
    echo "$(date) | EXECUTING SQL SCRIPT 10A_cont_indicator.sql..."
    result=$(psql -h $host -p $port -d $database -U $user -t -c "\i ./10A_cont_indicator.sql")
    if [ -z "$result" ]; then
        cont_finished=true
    fi

    # 10B
    echo "$(date) | EXECUTING SQL SCRIPT 10B_dup_indicator.sql..."
    result=$(psql -h $host -p $port -d $database -U $user -f ./10B_dup_indicator.sql)
    if [ -z "$result" ]; then
        dup_finished=true
    fi

    loop_count=$((loop_count+1))

    if [[ "$cont_finished" == "true" && "$dup_finished" == "true" ]]; then
        echo "Finished processing all data."
        break
    fi

    if [[ "$loop_count" -eq 10000 ]]; then
        echo "Loop count reached the limit. Exiting..."
        break
    fi
done
