#!/usr/bin/env python
"""
Author: Héctor Ochoa Ortiz
Date: 2024-07-11
"""

import requests
from urllib.parse import urljoin
from tqdm import tqdm
import pandas as pd
import time

api_base_url = "https://tasking-manager-tm4-production-api.hotosm.org/api/v2/"
endpoint = "projects"
headers = {
    "Accept-Language": "en",
    "accept": "application/json"
}
payload = {
    "projectStatuses": "ARCHIVED,PUBLISHED",
    "mappingTypes": "BUILDINGS,ROADS",
    "mappingTypesExact": False,
}
temp_data = {
    "pagination": {
        "nextNum": 1
    }
}
project_percentage_mapped = 100
#project_percentage_validated = 100

projects: list[dict] = []
pbar = tqdm(unit="project(s)")

while temp_data["pagination"]["nextNum"] is not None:
    payload.update({"page": int(temp_data["pagination"]["nextNum"])})
    while True:
        response = requests.get(
                        urljoin(api_base_url, endpoint),
                        headers=headers,
                        params=payload,
                        verify=True
                    )
        if response.status_code == 200:
            break  # Success

        if response.status_code == 502 or response.status_code == 504:
            # HOTOSM API gives 502 or 504 quite often for no apparent reason
            print("Received a " + str(response.status_code) +
                    ", trying again in 3 seconds...")
            time.sleep(3)  # Sleep 3 seconds and try again

        else:
            print(f"Request failed with status code: {response.status_code}")
            raise Exception(response.json())
    
    temp_data = response.json()
    projects += temp_data["results"]
    if int(temp_data["pagination"]["page"]) == 1:
        pbar.total = temp_data["pagination"]["total"]
        pbar.refresh()
    pbar.update(len(temp_data["results"]))

projects_df = pd.DataFrame.from_dict(projects)
selected_projects = projects_df[(projects_df['percentMapped'] == project_percentage_mapped)]  # & (projects_df['percentValidated'] == project_percentage_validated)]

with open("project_ids.txt", "w") as f:
    for proj_id in selected_projects["projectId"]:
        f.write(str(proj_id) + "\n")