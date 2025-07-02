#!/usr/bin/env python

import s2geometry as s2
import os
import shapely
from sqlalchemy import create_engine, text
from tqdm import tqdm
from config import database_host as host, database_port as port, database_name as database, database_user as user, database_password as password

# Set working directory as the same one where the file is located
os.chdir(os.path.dirname(os.path.abspath(__file__)))
data_dir = 'data'

# PostgreSQL parameters
engine = create_engine(f'postgresql://{user}:{password}@{host}:{port}/{database}')

# Define the S2 cell level
s2_level = 4 # https://sites.research.google/gr/open-buildings/#open-buildings-download

# Read the project ids
with open('project_ids.txt', 'r') as f:
    project_ids = f.read().splitlines()

# Check selected projects in the database
with engine.connect() as conn:
    try:
        result = conn.execute(text(f"SELECT distinct(sp.proj_id) FROM selected_projects sp WHERE sp.typename = 'BUILDINGS';"))
        project_ids = [row[0] for row in result.fetchall()]
    except Exception as e:
        print(f"Error executing query: {e}")

# Order the project ids
project_ids.sort()

# Create the s2 cell covering for each project file
with open('s2_cells.csv', 'w') as s2f:
    s2f.write(f'project_id,cell_ids\n')

    # Iterate through the project ids
    for project_id in tqdm(project_ids, desc="Processing projects", unit="project"):

        # Wrapping polygon (area of interest)
        with open(os.path.join(data_dir, f'project_{project_id}_aoi.geojson'), 'r') as f:
            aoi = shapely.from_geojson(f.read())


        # Iterate through the S2 cells
        coverer = s2.S2RegionCoverer()
        coverer.set_fixed_level(s2_level)
        coverer.set_max_cells(1000)

        region_bounds = aoi.bounds
        s2_lat_lng_rect = s2.S2LatLngRect.FromPointPair(
            s2.S2LatLng.FromDegrees(region_bounds[1], region_bounds[0]),
            s2.S2LatLng.FromDegrees(region_bounds[3], region_bounds[2]))
        cells = [cell.ToToken() for cell in coverer.GetCovering(s2_lat_lng_rect)]

        # Append the cell ids to the file
        s2f.write(f'{project_id},{";".join(cells)}\n')
    
print('Done')
