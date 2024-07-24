#!/usr/bin/env python
"""
This is a Python script for processing HOTOSM project data and storing it in a SQL database.
Author: Héctor Ochoa Ortiz
Date: 2024-07-11
"""

import json
from tqdm import tqdm
import psycopg2

proj_ids_filename = "project_ids.txt"

database_host = "localhost"
database_port = "5432"
database_name = "hotosm"
database_user = "postgres"
database_password = "postgres"

if __name__ == "__main__":
    # Connect to the database
    conn = psycopg2.connect(
        host=database_host,
        database=database_name,
        port=database_port,
        user=database_user,
        password=database_password
    )

    # Create a cursor object to interact with the database
    cursor = conn.cursor()

    # Create the projects table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY,
            priority VARCHAR(255),
            difficulty VARCHAR(255)
            created DATE,
            last_updated DATE
        )
    """)
    conn.commit()

    # Create the mapping types table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS mapping_types (
            typename VARCHAR(255),
            proj_id INTEGER,
            PRIMARY KEY (typename, proj_id),
            FOREIGN KEY (proj_id) REFERENCES projects (id)
        )
    """)
    conn.commit()


    # Create the mapping interests table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS mapping_interest (
            int_id INTEGER,
            int_name VARCHAR(255),
            proj_id INTEGER,
            PRIMARY KEY (int_id, proj_id),
            FOREIGN KEY (proj_id) REFERENCES projects (id)
        )
    """)
    conn.commit()

    # Create the countries table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS mapping_interest (
            country_name VARCHAR(255),
            proj_id INTEGER,
            PRIMARY KEY (country_name, proj_id),
            FOREIGN KEY (proj_id) REFERENCES projects (id)
        )
    """)
    conn.commit()

    # Load project IDs
    with open(proj_ids_filename) as f:
        input_data = [int(line.strip()) for line in f]

    for proj_id in tqdm(input_data, unit="project(s)"):
        with open(f"data/project_{str(proj_id)}.json") as f:
            data = json.load(f)

            # Process data and store it in SQL database
            cursor.execute(f"""
                INSERT INTO projects (id, priority, difficulty, perc_mapped, perc_validated)
                VALUES ('{proj_id}', '{data["projectPriority"]}', '{data["difficulty"]}', {data["percentMapped"]}, {data["percentValidated"]})
            """)
            conn.commit()

            # Insert mapping types into mapping_types table
            for m in data["mappingTypes"]:
                cursor.execute(f"""
                    INSERT INTO mapping_types (typename, proj_id)
                    VALUES ('{m}', {proj_id})
                """)
                conn.commit()

            # Insert mapping interests into mapping_interest table
            for i in data["interests"]:
                cursor.execute(f"""
                    INSERT INTO mapping_interest (int_id, int_name, proj_id)
                    VALUES ({i["id"]}, '{i["name"]}', {proj_id})
                """)
                conn.commit()

            # Insert countries into countries table
            for c in data["countryTag"]:
                cursor.execute(f"""
                    INSERT INTO countries (country_name, proj_id)
                    VALUES ('{c}', {proj_id})
                """)
                conn.commit()

    # Close the database cursor and the connection
    cursor.close()
    conn.close()