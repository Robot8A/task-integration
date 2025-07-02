#!/bin/bash

# Transform OSM roads to SQL
echo "********************************"
echo "TRANSFORMING OSM ROADS TO SQL..."
echo "********************************"

# Read project numbers from a file
PROJECT_FILE="project_ids.txt"
project_ids=$(cat "$PROJECT_FILE")
num_project_ids=$(echo "$project_ids" | wc -w)
table_name="roads_pre_partition"
current_project=1
project_id_column_created=false

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

        if [ $project_id_column_created = true ]; then
            psql -h ${host} -p ${port} -d ${database} -U ${user} -c "ALTER TABLE ${table_name} ALTER COLUMN project_id SET DEFAULT ${project_id};"
        fi
        

        echo "Transforming roads of project ${project_id}"

        # Unzip file
        unzip -o data/osm_roads_${project_id}.zip -d $temp_dir

        # Preprocess GeoJSON to remove MultiLineString geometries (relations type=route, route=road)
        jq '.features |= map(select(.geometry.type == "LineString"))' \
        $temp_dir/hotosm_project_${project_id}_roads_lines_geojson.geojson > $temp_dir/filtered_roads_${project_id}.geojson

        # Transform GeoJSON to SQL
        ogr2ogr -f "PostgreSQL" PG:"host=${host} port=${port} dbname=${database} user=${user} password=${PGPASSWORD}" $temp_dir/filtered_roads_${project_id}.geojson -nln ${table_name} -nlt LINESTRING -lco GEOMETRY_NAME=geom -lco FID=gid -append -update
    
        if [ $? -ne 0 ]; then
            echo "Failed to transform roads of project ${project_id}"
            exit 1
        fi

        if [ $project_id_column_created = false ]; then
            psql -h ${host} -p ${port} -d ${database} -U ${user} -c "ALTER TABLE ${table_name} ADD COLUMN project_id INTEGER DEFAULT ${project_id};"
            project_id_column_created=true
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

return 0
