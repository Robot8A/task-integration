#!/bin/bash

API_ENDPOINT="https://tasking-manager-tm4-production-api.hotosm.org/api/v2/"

# Read project numbers from a file
PROJECT_FILE="project_ids.txt"
project_ids=$(cat "$PROJECT_FILE")
num_project_ids=$(echo "$project_ids" | wc -w)

# Create the data subfolder if it doesn't exist
mkdir -p data

# Download project data
echo "***************************"
echo "DOWNLOADING PROJECT DATA..."
echo "***************************"
PAYLOAD="{\"as_file\": false, \"abbreviated\": true}"
current_project=1
for project_id in $project_ids; do
    while : ; do
        if [ ! -f "data/project_${project_id}.json" ]; then
            echo "Downloading data/project_${project_id}.json ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -H "Accept-Language: en;accept: application/json" -d "${PAYLOAD}" "${API_ENDPOINT}projects/${project_id}/" > "data/project_${project_id}.json"
            if [ $? -eq 0 ]; then
                break
            fi
            echo "Failed to download project ${project_id}. Retrying in 3 seconds..."
            sleep 3
        else
            echo "File data/project_${project_id}.json already exists. Skipping download."
            break
        fi
    done
    current_project=$((current_project + 1))
done

# Download project OSM buildings
echo "****************************"
echo "DOWNLOADING OSM BUILDINGS..."
echo "****************************"
API_ENDPOINT="https://production-raw-data-api.s3.amazonaws.com/TM/"
PAYLOAD="{}"
current_project=1
for project_id in $project_ids; do
    while : ; do
        if [ ! -f "data/osm_buildings_${project_id}.zip" ]; then
            echo "Downloading data/osm_buildings_${project_id}.zip ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -d "${PAYLOAD}" "${API_ENDPOINT}hotosm_project_${project_id}/buildings/polygons/hotosm_project_${project_id}_buildings_polygons_geojson.zip" > "data/osm_buildings_${project_id}.zip"
            if [ $? -eq 0 ]; then
                if ! file --mime-type "data/osm_buildings_${project_id}.zip" | grep -q "application/zip"; then
                    if cat "data/osm_buildings_${project_id}.zip" | grep -q "NoSuchKey"; then
                        echo "Project ${project_id} has no buildings, deleting response."
                        rm "data/osm_buildings_${project_id}.zip"
                    else
                        echo "Failed to download project ${project_id}."
                        exit 1
                    fi
                fi
                break
            fi
            echo "Failed to download project ${project_id}. Retrying in 3 seconds..."
            sleep 3
        else
            echo "File data/osm_buildings_${project_id}.zip already exists. Skipping download."
            break
        fi
    done
    current_project=$((current_project + 1))
done

# Download project OSM roads
echo "************************"
echo "DOWNLOADING OSM ROADS..."
echo "************************"
PAYLOAD="{}"
current_project=1
for project_id in $project_ids; do
    while : ; do
        if [ ! -f "data/osm_roads_${project_id}.zip" ]; then
            echo "Downloading data/osm_roads_${project_id}.zip ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -d "${PAYLOAD}" "${API_ENDPOINT}hotosm_project_${project_id}/roads/lines/hotosm_project_${project_id}_roads_lines_geojson.zip" > "data/osm_roads_${project_id}.zip"
            if [ $? -eq 0 ]; then
                if ! file --mime-type "data/osm_roads_${project_id}.zip" | grep -q "application/zip"; then
                    if cat "data/osm_roads_${project_id}.zip" | grep -q "NoSuchKey"; then
                        echo "Project ${project_id} has no roads, deleting response."
                        rm "data/osm_roads_${project_id}.zip"
                    else
                        echo "Failed to download project ${project_id}."
                        exit 1
                    fi
                fi
                break
            fi
            echo "Failed to download project ${project_id}. Retrying in 3 seconds..."
            sleep 3
        else
            echo "File data/osm_roads_${project_id}.zip already exists. Skipping download."
            break
        fi
    done
    current_project=$((current_project + 1))
done

# Download project task grid
echo "***************************"
echo "DOWNLOADING PROJECT GRID..."
echo "***************************"
PAYLOAD="{\"as_file\": false}"
current_project=1
for project_id in $project_ids; do
    while : ; do
        if [ ! -f "data/grid_${project_id}.geojson" ]; then
            echo "Downloading data/grid_${project_id}.geojson ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -H "Accept-Language: en;accept: application/json" -d "${PAYLOAD}" "${API_ENDPOINT}projects/${project_id}/tasks/" > "data/grid_${project_id}.geojson"
            if [ $? -eq 0 ]; then
                break
            fi
            echo "Failed to download project ${project_id}. Retrying in 3 seconds..."
            sleep 3
        else
            echo "File data/grid_${project_id}.json already exists. Skipping download."
            break
        fi
    done
    current_project=$((current_project + 1))
done
