#!/bin/bash

# Transform OSM buildings to SQL
echo "************************************"
echo "TRANSFORMING OSM BUILDINGS TO SQL..."
echo "************************************"

# Read project numbers from a file
PROJECT_FILE="project_ids.txt"
project_ids=$(cat "$PROJECT_FILE")
num_project_ids=$(echo "$project_ids" | wc -w)
table_name="buildings_pre_partition"
current_project=1
project_id_column_created=false

# PostgreSQL parameters
host=localhost
port=5432
database=hotosm
user=postgres
export PGPASSWORD=postgres

# Calculate progress bar width
progress_bar_width=50

for project_id in $project_ids; do
    if [ -f "data/osm_buildings_${project_id}.zip" ]; then
        # Create a temporary directory
        temp_dir=$(mktemp -d)

        # Check if the temporary directory was created successfully
        if [ ! -d "$temp_dir" ]; then
            echo "Failed to create temporary directory"
            exit 1
        fi

        if [ $project_id_column_created = true ]; then
            psql -h localhost -p 5432 -d hotosm -U postgres -c "ALTER TABLE ${table_name} ALTER COLUMN project_id SET DEFAULT ${project_id};"
        fi

        echo "Transforming buildings of project ${project_id}"

        # Unzip file
        unzip -o data/osm_buildings_${project_id}.zip -d $temp_dir

        # Transform GeoJSON to SQL
        ogr2ogr -f "PostgreSQL" PG:"host=${host} port=5432 dbname=hotosm user=postgres password=postgres" $temp_dir/hotosm_project_${project_id}_buildings_polygons_geojson.geojson -nln ${table_name} -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=gid -append -update
    
        if [ $? -ne 0 ]; then
            echo "Failed to transform buildings of project ${project_id}"
            exit 1
        fi

        if [ $project_id_column_created = false ]; then
            psql -h localhost -p 5432 -d hotosm -U postgres -c "ALTER TABLE ${table_name} ADD COLUMN project_id INTEGER DEFAULT ${project_id};"
            project_id_column_created=true
        fi

        # Remove temporary directory
        rm -rf $temp_dir
    else
        echo "File data/osm_buildings_${project_id}.zip does not exist. Skipping transformation."
    fi
    
    # Calculate progress percentage
    progress=$((current_project * 100 / num_project_ids))
    
    # Calculate number of progress bar characters
    progress_bar_chars=$((progress * progress_bar_width / 100))
    
    # Print progress bar
    printf "\nProgress: [%-${progress_bar_width}s] %d%%\n" $(printf "%${progress_bar_chars}s" | tr ' ' '#') $progress

    current_project=$((current_project + 1))
done

return 0
