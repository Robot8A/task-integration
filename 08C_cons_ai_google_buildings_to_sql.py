import os
import sys
import shapely
from tqdm import tqdm
import pandas as pd
import geopandas as gpd
from sqlalchemy import create_engine, text
import requests

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

# PostgreSQL parameters
host = "localhost"
port = 5432
database = "hotosm"
user = "postgres"
password = "postgres"
engine = create_engine(f'postgresql://{user}:{password}@{host}:{port}/{database}')
table_name = "google_buildings"
table_name_log = "s2_cell_google_building_uploaded"

# Create the buildings table and the log table on the database
with engine.connect() as conn:
    conn.execute(text(f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            project_id INTEGER,
            s2_cell_token VARCHAR(3),
            geom GEOMETRY (POLYGON, 4326)
        );
        CREATE TABLE IF NOT EXISTS {table_name_log} (
            s2_cell_token VARCHAR(3),
            project_id INTEGER
        );
    """))
    conn.commit()

    for s2_cell in (s2pbar := tqdm(s2_cells, desc=f"Processing cells", leave=True)):
        s2pbar.set_description_str(f"Processing cell {s2_cell}")

        # Check if the projects for this s2 cell are selected in the database and not uploaded yet
        selected_projects = conn.execute(text(f"""
        SELECT proj_id
        FROM selected_projects
        WHERE typename = 'BUILDINGS' AND proj_id IN ({','.join(map(str, data_dict[s2_cell]))})
        AND (indicator_cons_ai IS NULL OR indicator_cons_ai < 8)
        """)).fetchall()
        selected_project_ids = [row[0] for row in selected_projects]

        if selected_project_ids.__len__() == 0:
            print(f"{pd.Timestamp.now()} | All projects for s2 cell {s2_cell} are uploaded already. Skipping transformation.", file=sys.stderr)
        else:
            # Download the buildings file
            file_path = os.path.join(data_dir, f'{s2_cell}_buildings.csv.gz')
            if not os.path.exists(file_path):
                url = f'https://storage.googleapis.com/open-buildings-data/v3/polygons_s2_level_4_gzip/{s2_cell}_buildings.csv.gz'
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
                                with tqdm(total=total_length, unit='B', unit_scale=True, desc=f'Downloading cell {s2_cell}', leave=False) as pbar:
                                    for chunk in response.iter_content(chunk_size=chunk_size):
                                        if chunk:
                                            f.write(chunk)
                                            pbar.update(len(chunk))
                    else:
                        print(f'{pd.Timestamp.now()} | Error downloading {url} - Status code: {response.status_code}', file=sys.stderr)
            else:
                print(f'{pd.Timestamp.now()} | s2 cell {s2_cell} buildings already downloaded', file=sys.stderr)

            # Check if the buildings file exists
            if not os.path.isfile(file_path):
                print(f"{pd.Timestamp.now()} | File data/{s2_cell}_buildings.csv.gz does not exist. Skipping transformation.", file=sys.stderr)
            else: 
                if len(selected_project_ids) > 0:
                    # Read the gzipped CSV file in chunks
                    chunksize = 100000
                    with pd.read_csv(f"data/{s2_cell}_buildings.csv.gz", compression='gzip', chunksize=chunksize) as reader:
                        for chunk in tqdm(reader, desc="Reading CSV in chunks", leave=False):
                            chunk['geom'] = gpd.GeoSeries.from_wkt(chunk['geometry'])
                            chunk.drop('geometry', axis=1, inplace=True)
                            chunk = gpd.GeoDataFrame(chunk, geometry='geom', crs="EPSG:4326")

                            # If some geometry is multipolygon instead of polygon, convert to polygon
                            for index, row in chunk.iterrows():
                                if row['geom'].geom_type == 'MultiPolygon':
                                    # Get the first polygon
                                    polygon = row['geom'].geoms[0]
                                    chunk.at[index, 'geom'] = polygon
                                    for i in range(1, len(row['geom'].geoms)):
                                        chunk = pd.concat([chunk, gpd.GeoDataFrame([{'geom': row['geom'].geoms[i]}], crs=chunk.crs, geometry='geom')], ignore_index=True)
                                    
                            for project_id in (prpbar := tqdm(selected_project_ids, desc=f"Processing projects", leave=False)):
                                prpbar.set_description_str(f"Processing project {project_id}")

                                # Check if the project-s2 cell pairs is processed
                                result = conn.execute(text(f"""
                                SELECT COUNT(*)
                                FROM {table_name_log}
                                WHERE s2_cell_token = '{s2_cell}' AND project_id = {project_id}
                                """)).fetchone()
                                    
                                if result[0] == 0:
                                    # Read the Area of Interest of the given project
                                    with open(os.path.join(data_dir, f'project_{project_id}_aoi.geojson'), 'r') as f:
                                        aoi = shapely.from_geojson(f.read())
                                    
                                    # Filter buildings that are within the AOI
                                    def is_within_aoi(geometry):
                                        try:
                                            return aoi.contains(geometry)
                                        except shapely.errors.GEOSException as e:
                                            return False
                                    
                                    buildings_s2 = chunk.loc[chunk['geom'].apply(is_within_aoi)]
                                
                                    # Insert the data into the database
                                    if not buildings_s2.empty:
                                        buildings_s2 = buildings_s2.copy()
                                        buildings_s2['project_id'] = project_id
                                        buildings_s2['s2_cell_token'] = s2_cell
                                        buildings_s2 = buildings_s2[['project_id', 's2_cell_token', 'geom']]
                                        buildings_s2.to_postgis(name=table_name, con=conn, if_exists='append', index=False, dtype={'geom': 'Geometry'})

                    # Mark the project-s2 cell pairs as processed
                    conn.execute(text(f"""
                    INSERT INTO {table_name_log} (s2_cell_token, project_id)
                    SELECT '{s2_cell}', proj_id as project_id
                    FROM selected_projects
                    WHERE typename = 'BUILDINGS' AND proj_id IN ({','.join(map(str, selected_project_ids))});
                    """))
                    conn.commit()

            # Delete the buildings file
            os.remove(file_path)

        # If all the s2 cells of a given project have been uploaded, update selected_projects indicator_cons_ai to 8
        for project_id in selected_project_ids:
            # Get the s2 cells for that project
            s2_cells_project = data_df[data_df['project_id'] == project_id]['cell_ids'].str.split(';').explode().unique()
            
            # Check if all the s2 cells have been uploaded
            uploaded_s2_cells = conn.execute(text(f"""
            SELECT s2_cell_token
            FROM {table_name}
            WHERE project_id = {project_id}
            """)).fetchall()
            uploaded_s2_cells = [row[0] for row in uploaded_s2_cells]

            if set(s2_cells_project) == set(uploaded_s2_cells):
                # Update the indicator_cons_ai to 8
                conn.execute(text(f"""
                UPDATE selected_projects
                SET indicator_cons_ai = 8
                WHERE proj_id = {project_id}
                AND typename = 'BUILDINGS'
                AND (indicator_cons_ai IS NULL OR indicator_cons_ai < 8)
                """))
                conn.commit()      
