CREATE MATERIALIZED VIEW geometry_consistency
WITH (parallel_workers = 8) AS
WITH project_ids AS (
    SELECT proj_id
    FROM selected_projects
    WHERE typename = 'BUILDINGS'
    LIMIT 10
)
SELECT project_ids.proj_id, cgc.* 
FROM project_ids
JOIN LATERAL calculate_gearys_c_for_project(project_ids.proj_id) AS cgc ON true;