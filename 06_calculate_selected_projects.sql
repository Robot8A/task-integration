DROP TABLE IF EXISTS selected_projects;
CREATE TABLE selected_projects AS
SELECT proj_id, typename, 6 AS indicator_cont_dup, 6 AS indicator_cons, NULL AS indicator_cons_ai
FROM public.mapping_types
WHERE (typename = 'ROADS' OR typename = 'BUILDINGS')
AND project_has_fully_adjacent_cells(proj_id);

CREATE INDEX ON selected_projects (proj_id);