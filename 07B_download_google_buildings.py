#!/usr/bin/env python

import s2geometry
import os
import requests
import shapely
from sqlalchemy import create_engine, text
from tqdm import tqdm

# Set working directory as the same one where the file is located
os.chdir(os.path.dirname(os.path.abspath(__file__)))
data_dir = 'data'

# PostgreSQL parameters
host = "localhost"
port = 5432
database = "hotosm"
user = "postgres"
password = "postgres"
engine = create_engine(f'postgresql://{user}:{password}@{host}:{port}/{database}')
table_name = "google_buildings"
table_name_log = "s2_cell_google_building_uploaded"

# Create the buildings table on the database
with engine.connect() as conn:
    conn.execute(text(f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            project_id INTEGER,
            s2_cell_token VARCHAR(3),
            geom GEOMETRY (POLYGON, 4326)
        );
    """))
    conn.commit()

# Define the S2 cell level
s2_level = 4 # https://sites.research.google/gr/open-buildings/#open-buildings-download

# Read the project ids
with open('project_ids.txt', 'r') as f:
    project_ids = f.read().splitlines()

# Check which project ids are already in the database, to avoid downloading buildings again
with engine.connect() as conn:
    try:
        result = conn.execute(text(f"SELECT distinct(project_id) FROM {table_name_log} WHERE project_id IN ({','.join(project_ids)});"))
        existing_project_ids = {row[0] for row in result.fetchall()}
        project_ids = [pid for pid in project_ids if pid not in existing_project_ids]
    except Exception as e:
        print(f"Error executing query: {e}")

# Check if the project ids are not within the selected projects in the database
with engine.connect() as conn:
    try:
        result = conn.execute(text(f"SELECT distinct(sp.proj_id) FROM selected_projects sp WHERE sp.typename = 'BUILDINGS' AND sp.proj_id IN ({','.join(project_ids)});"))
        project_ids = list({row[0] for row in result.fetchall()})
    except Exception as e:
        print(f"Error executing query: {e}")

# Order the project ids
project_ids.sort()

# Create the s2 cell covering for each project file
with open('s2_cells.csv', 'w') as s2f:
    s2f.write(f'project_id,cell_ids\n')

    # Iterate through the project ids
    for project_id in project_ids:

        # Wrapping polygon (area of interest)
        with open(os.path.join(data_dir,f'project_{project_id}_aoi.geojson'), 'r') as f:
            aoi = shapely.from_geojson(f.read())

        # Convert from shapely to s2 geometry
        s2aoi = s2geometry.S2Polygon()
        for part in aoi.geoms:  # Iterate over each part of the multipolygon
            outer_loops = []
            inner_loops = []
            for lng, lat in part.exterior.coords:  # Outer ring
                outer_loops.append(s2geometry.S2LatLng.FromDegrees(lat, lng).ToPoint())

            loop = s2geometry.S2Loop(outer_loops)
            loop.Normalize()  # Normalize to ensure it represents the smaller region
            s2aoi.InitNested([loop])  # InitNested takes a list of loops

            for inner in part.interiors:  # Inner rings (if any)
                for lng, lat in reversed(inner.coords):
                    inner_loops.append(s2geometry.S2LatLng.FromDegrees(lat, lng).ToPoint())
                loop = s2geometry.S2Loop(inner_loops)
                loop.Normalize()  # Normalize to ensure it represents the smaller region
                s2aoi.InitNested([loop])  # InitNested takes a list of loops

        # Get the S2 cell covering the wrapping polygon
        covering = s2geometry.S2RegionCoverer()
        covering.set_fixed_level(s2_level)
        covering.set_max_cells(100)

        cells = [cell.ToToken() for cell in covering.GetCovering(s2aoi)]

        # Append the cell ids to a file
        s2f.write(f'{project_id},{";".join(cells)}\n')

        # Download the buildings for the given cells
        for cell in cells:
            file_path = os.path.join(data_dir, f'{cell}_buildings.csv.gz')
            if not os.path.exists(file_path):
                print(f'Project {project_id} | Downloading s2 cell {cell} buildings...')
                url = f'https://storage.googleapis.com/open-buildings-data/v3/polygons_s2_level_4_gzip/{cell}_buildings.csv.gz'
                with requests.get(url, stream=True) as response:
                    if response.status_code == 200:
                        total_length = response.headers.get('content-length')
                        if total_length is None:  # no content length header
                            with open(file_path, 'wb') as f:
                                f.write(response.content)
                        else:
                            total_length = int(total_length)
                            chunk_size = 1024
                            with open(file_path, 'wb') as f:
                                with tqdm(total=total_length, unit='B', unit_scale=True, desc=file_path) as pbar:
                                    for chunk in response.iter_content(chunk_size=chunk_size):
                                        if chunk:
                                            f.write(chunk)
                                            pbar.update(len(chunk))
                        print(f'Project {project_id} | s2 cell {cell} buildings downloaded successfully')
                    else:
                        print(f'Project {project_id} | Error downloading {url} - Status code: {response.status_code}')
            else:
                print(f'Project {project_id} | s2 cell {cell} buildings already downloaded')
    
print('Done')
