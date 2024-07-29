#!/bin/bash

# Transform OSM grids to SQL
echo "********************************"
echo "TRANSFORMING OSM GRIDS TO SQL..."
echo "********************************"

# Read project numbers from a file
PROJECT_FILE="project_ids.txt"
project_ids=$(cat "$PROJECT_FILE")
num_project_ids=$(echo "$project_ids" | wc -w)
table_name="hotosm_grids"
current_project=1

export PGPASSWORD=postgres

# Calculate progress bar width
progress_bar_width=50

for project_id in $project_ids; do
    if [ -f "data/grid_${project_id}.geojson" ]; then

        if [ $current_project -ne 1 ]; then
            psql -h localhost -p 5432 -d hotosm -U postgres -c "ALTER TABLE ${table_name} ALTER COLUMN project_id SET DEFAULT ${project_id};"
        fi
        
        # Transform GeoJSON to SQL
        ogr2ogr -f "PostgreSQL" PG:"host=localhost port=5432 dbname=hotosm user=postgres password=postgres" data/grid_${project_id}.geojson -nln ${table_name} -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=gid -append -update
    
        if [ $? -ne 0 ]; then
            echo "Failed to transform grids of project ${project_id}"
            exit 1
        fi

        if [ $current_project -eq 1 ]; then
            psql -h localhost -p 5432 -d hotosm -U postgres -c "ALTER TABLE ${table_name} ADD COLUMN project_id INTEGER DEFAULT ${project_id};"
        fi
        
    else
        echo "File data/grid_${project_id}.geojson does not exist. Skipping transformation."
    fi
    
    # Calculate progress percentage
    progress=$((current_project * 100 / num_project_ids))
    
    # Calculate number of progress bar characters
    progress_bar_chars=$((progress * progress_bar_width / 100))
    
    # Print progress bar
    printf "\nProgress: [%-${progress_bar_width}s] %d%%\n" $(printf "%${progress_bar_chars}s" | tr ' ' '#') $progress
    # Print newline after progress bar
    echo

    current_project=$((current_project + 1))
done
