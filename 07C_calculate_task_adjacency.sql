CREATE MATERIALIZED VIEW adjacent_tasks AS
WITH project_ids AS (
    SELECT proj_id
    FROM selected_projects
    WHERE typename = 'BUILDINGS'
),
tasks AS (
    SELECT p.proj_id, g.taskid, ST_MakeValid(g.geom) AS geom
    FROM project_ids p
    JOIN grids g ON g.project_id = p.proj_id
),
adjacent_tasks AS (
    SELECT t1.proj_id, t1.taskid AS task_id, t2.taskid AS adjacent_task_id
    FROM tasks t1
    JOIN tasks t2 ON ST_Touches(t1.geom, t2.geom)
    WHERE t1.taskid <> t2.taskid
)
SELECT proj_id AS project_id, task_id, adjacent_task_id
FROM adjacent_tasks;