CREATE MATERIALIZED VIEW selected_projects
WITH (parallel_workers = 16) AS
SELECT proj_id, typename
FROM public.mapping_types
WHERE (typename = 'ROADS' OR typename = 'BUILDINGS')
AND project_has_fully_adjacent_cells(proj_id);
