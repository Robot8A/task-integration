CREATE MATERIALIZED VIEW adjacent_tasks PARALLEL 4 AS
WITH project_ids AS (
    SELECT DISTINCT proj_id
    FROM public.mapping_types
    WHERE typename = 'BUILDINGS'
    AND project_has_fully_adjacent_cells(proj_id)
),
tasks AS (
    SELECT p.proj_id, hg.taskid, ST_MakeValid(hg.geom) AS geom
    FROM project_ids p
    JOIN hotosm_grids hg ON hg.project_id = p.proj_id
)
...