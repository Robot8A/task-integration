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
    filename="data/project_${project_id}.json"
    while : ; do
        if [ ! -f "${filename}" ]; then
            echo "Downloading ${filename} ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -H "Accept-Language: en;accept: application/json" -d "${PAYLOAD}" "${API_ENDPOINT}projects/${project_id}/" > "${filename}"
            if [ $? -eq 0 ]; then
                break
            fi
            echo "Failed to download project ${project_id}. Retrying in 3 seconds..."
            sleep 3
        else
            echo "File ${filename} already exists. Skipping download."
            break
        fi
    done
    current_project=$((current_project + 1))
done

# Download project data
echo "****************************************"
echo "DOWNLOADING PROJECT STATISTICS DATA..."
echo "****************************************"
PAYLOAD="{}"
current_project=1
for project_id in $project_ids; do
    filename="data/project_${project_id}_statistics.json"
    while : ; do
        if [ ! -f "${filename}" ]; then
            echo "Downloading ${filename} ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -H "Accept-Language: en;accept: application/json" -d "${PAYLOAD}" "${API_ENDPOINT}projects/${project_id}/statistics/" > "${filename}"
            if [ $? -eq 0 ]; then
                break
            fi
            echo "Failed to download project ${project_id}. Retrying in 3 seconds..."
            sleep 3
        else
            echo "File ${filename} already exists. Skipping download."
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
    filename="data/osm_buildings_${project_id}.zip"
    while : ; do
        if [ ! -f "${filename}" ]; then
            echo "Downloading ${filename} ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -d "${PAYLOAD}" "${API_ENDPOINT}hotosm_project_${project_id}/buildings/polygons/hotosm_project_${project_id}_buildings_polygons_geojson.zip" > "${filename}"
            if [ $? -eq 0 ]; then
                if ! file --mime-type "${filename}" | grep -q "application/zip"; then
                    if cat "${filename}" | grep -q "NoSuchKey"; then
                        echo "Project ${project_id} has no buildings, deleting response."
                        rm "${filename}"
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
            echo "File ${filename} already exists. Skipping download."
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
    filename="data/osm_roads_${project_id}.zip"
    while : ; do
        if [ ! -f "${filename}" ]; then
            echo "Downloading ${filename} ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -d "${PAYLOAD}" "${API_ENDPOINT}hotosm_project_${project_id}/roads/lines/hotosm_project_${project_id}_roads_lines_geojson.zip" > "${filename}"
            if [ $? -eq 0 ]; then
                if ! file --mime-type "${filename}" | grep -q "application/zip"; then
                    if cat "${filename}" | grep -q "NoSuchKey"; then
                        echo "Project ${project_id} has no roads, deleting response."
                        rm "${filename}"
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
            echo "File ${filename} already exists. Skipping download."
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
    filename="data/grid_${project_id}.geojson"
    while : ; do
        if [ ! -f "${filename}" ]; then
            echo "Downloading ${filename} ... STATUS(${current_project} of ${num_project_ids})"
            curl -s -X GET -H "Accept-Language: en;accept: application/json" -d "${PAYLOAD}" "${API_ENDPOINT}projects/${project_id}/tasks/" > "${filename}"
            if [ $? -eq 0 ]; then
                break
            fi
            echo "Failed to download project ${project_id}. Retrying in 3 seconds..."
            sleep 3
        else
            echo "File ${filename} already exists. Skipping download."
            break
        fi
    done
    current_project=$((current_project + 1))
done
