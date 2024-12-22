CREATE MATERIALIZED VIEW avg_vertices_per_building_per_task
WITH (parallel_workers = 8) AS
WITH project_ids AS (
    SELECT proj_id
    FROM selected_projects
    WHERE typename = 'BUILDINGS'
    LIMIT 10
),
tasks AS (
    SELECT p.proj_id, hg.taskid
    FROM project_ids p
    JOIN hotosm_grids hg ON hg.project_id = p.proj_id
)
--- Calculate the average number of vertices of the buildings in each task
SELECT t.proj_id, t.taskid, avg_data.avg_vertices, avg_data.buildings_count
FROM tasks t
CROSS JOIN LATERAL (SELECT * FROM calculate_avg_vertices_per_building_from_tasks(t.proj_id, ARRAY[t.taskid])) AS avg_data;