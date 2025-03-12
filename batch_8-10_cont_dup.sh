#!/bin/bash

# PostgreSQL parameters
host=localhost
port=5432
database=hotosm
user=postgres
export PGPASSWORD=postgres

loop_count=0

# Do an infinite loop
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
    psql -h $host -p $port -d $database -U $user -f ./10A_cont_indicator.sql

    # 10B
    echo "$(date) | EXECUTING SQL SCRIPT 10B_dup_indicator.sql..."
    psql -h $host -p $port -d $database -U $user -f ./10B_dup_indicator.sql

    loop_count=$((loop_count+1))

    if [ "$loop_count" -ge 100 ]; then
        echo "Reached loop count limit. Exiting..."
        break
    fi
done
