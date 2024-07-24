#!/bin/bash

# Transform OSM roads to SQL
echo "********************************"
echo "TRANSFORMING OSM ROADS TO SQL..."
echo "********************************"

# Read project numbers from a file
PROJECT_FILE="project_ids.txt"
project_ids=$(cat "$PROJECT_FILE")
num_project_ids=$(echo "$project_ids" | wc -w)
current_project=1

export PGPASSWORD=postgres

# Calculate progress bar width
progress_bar_width=50

for project_id in $project_ids; do
    if [ -f "data/osm_roads_${project_id}.zip" ]; then
        # Create a temporary directory
        temp_dir=$(mktemp -d)

        # Check if the temporary directory was created successfully
        if [ ! -d "$temp_dir" ]; then
            echo "Failed to create temporary directory"
            exit 1
        fi

        echo "Transforming roads of project ${project_id}"

        # Unzip file
        unzip -o data/osm_roads_${project_id}.zip -d $temp_dir

        # Transform GeoJSON to SQL
        ogr2ogr -f "PostgreSQL" PG:"host=localhost port=5432 dbname=hotosm user=postgres password=postgres" $temp_dir/hotosm_project_${project_id}_roads_lines_geojson.geojson -nln osm_roads -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=gid -append -update
    
        if [ $? -ne 0 ]; then
            echo "Failed to transform roads of project ${project_id}"
            exit 1
        fi

        # Remove temporary directory
        rm -rf $temp_dir
    else
        echo "File data/osm_roads_${project_id}.zip does not exist. Skipping transformation."
    fi
    
    # Calculate progress percentage
    progress=$((current_project * 100 / num_project_ids))
    
    # Calculate number of progress bar characters
    progress_bar_chars=$((progress * progress_bar_width / 100))
    
    # Print progress bar
    printf "\nProgress: [%-${progress_bar_width}s] %d%%\n" $(printf "%${progress_bar_chars}s" | tr ' ' '#') $progress

    current_project=$((current_project + 1))
done

# Remove duplicate roads
psql -h localhost -p 5432 -d hotosm -U postgres -c "DELETE FROM osm_roads a USING osm_roads b WHERE a.gid < b.gid AND a.osm_id = b.osm_id;"