import os
import subprocess
import sys
import tempfile
import shapely
from tqdm import tqdm
import pandas as pd
import geopandas as gpd
from sqlalchemy import create_engine, text

# Set working directory as the same one where the file is located
os.chdir(os.path.dirname(os.path.abspath(__file__)))
data_dir = 'data'

# Transform Google Open Buildings to SQL
print("********************************************")
print("TRANSFORMING GOOGLE OPEN BUILDINGS TO SQL...")
print("********************************************")

# Read project numbers from a file
PROJECT_FILE = "s2_cells.csv"
data_df = pd.read_csv(PROJECT_FILE)

# Get the unique s2 cells
s2_cells = data_df['cell_ids'].str.split(';').explode().unique()

# Store in a dictionary the project ids for each s2 cell
data_dict = {}
for s2_cell in s2_cells:
    data_dict[s2_cell] = data_df[data_df['cell_ids'].str.contains(s2_cell)]['project_id'].values
del data_df

# PostgreSQL parameters
host = "localhost"
port = 5432
database = "hotosm"
user = "postgres"
password = "postgres"
engine = create_engine(f'postgresql://{user}:{password}@{host}:{port}/{database}')
table_name = "google_buildings_pre_partition"

for s2_cell in tqdm(s2_cells, desc="Processing s2 cells"):
    # Check if the buildings file exists
    if not os.path.isfile(f"data/{s2_cell}_buildings.csv.gz"):
        print(f"File data/{s2_cell}_buildings.csv.gz does not exist. Skipping transformation.", file=sys.stderr)
    else:
        # Check if the projects for this s2 cell are selected in the database and not already in the buildings table
        with engine.connect() as conn:
            selected_projects = conn.execute(text(f"""
            SELECT proj_id
            FROM selected_projects
            WHERE typename = 'BUILDINGS' AND proj_id IN ({','.join(map(str, data_dict[s2_cell]))})
            AND proj_id NOT IN (
                SELECT project_id
                FROM {table_name}
                WHERE s2_cell_token = '{s2_cell}'
            );
            """)).fetchall()
        selected_project_ids = [row[0] for row in selected_projects]

        if selected_project_ids:
            # Create a temporary directory
            temp_dir = tempfile.mkdtemp()

            # Unzip file
            with open(f"{temp_dir}/{s2_cell}_buildings.csv", 'w') as f_out:
                subprocess.run(["gunzip", "-c", f"data/{s2_cell}_buildings.csv.gz"], stdout=f_out)

            # Read the file in chunks
            chunksize = 10000
            for chunk in tqdm(pd.read_csv(f"{temp_dir}/{s2_cell}_buildings.csv", chunksize=chunksize), desc="Processing chunks", leave=False):
                chunk['geom'] = gpd.GeoSeries.from_wkt(chunk['geometry'])
                chunk.drop('geometry', axis=1, inplace=True)
                chunk = gpd.GeoDataFrame(chunk, geometry='geom', crs="EPSG:4326")
            
                for project_id in tqdm(selected_project_ids, desc="Processing projects", leave=False):
                    # Read the Area of Interest of the given project
                    with open(os.path.join(data_dir, f'project_{project_id}_aoi.geojson'), 'r') as f:
                        aoi = shapely.from_geojson(f.read())
                    
                    with engine.connect() as conn:
                        # Filter buildings that are within the AOI
                        buildings_s2 = chunk.loc[chunk['geom'].apply(lambda x: aoi.contains(shapely.geometry.shape(x)))]
    
                        # Insert the data into the database
                        if not buildings_s2.empty:
                            buildings_s2 = buildings_s2.copy()
                            buildings_s2['project_id'] = project_id
                            buildings_s2['s2_cell_token'] = s2_cell
                            buildings_s2 = buildings_s2[['project_id', 's2_cell_token', 'geom']]
                            buildings_s2.to_postgis(name=table_name, con=conn, if_exists='append', index=False)
                            conn.commit()

            # Delete the temporary directory
            subprocess.run(["rm", "-rf", temp_dir])
