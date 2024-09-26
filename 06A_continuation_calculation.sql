-- Run this part multiple times until it alls gets done
WITH proj_ids AS (
	SELECT proj_id AS ids
	FROM public.mapping_types
	WHERE typename = 'ROADS'
    AND project_has_fully_adjacent_cells(proj_id)
    AND NOT EXISTS (
        SELECT co.project_id
        FROM continuation co
        WHERE co.project_id = proj_id
        AND grid_type = 'MOCKUP-POLY'
        LIMIT 1
        )
    LIMIT 200
)
INSERT INTO continuation (project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer)
SELECT project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer
FROM continuation(
	(SELECT array_agg(ids) FROM proj_ids),
	ARRAY[5.0, 10.0, 15.0],
    ARRAY['MOCKUP-POLY'],
    ARRAY['percentage']
)
ON CONFLICT (project_id, grid_type, shrink_distance, shrink_type) 
DO UPDATE SET 
    nodes_in_shrunk_grids = EXCLUDED.nodes_in_shrunk_grids,
    nodes_in_border_buffer = EXCLUDED.nodes_in_border_buffer,
    area_of_shrunk_grids = EXCLUDED.area_of_shrunk_grids,
    area_of_border_buffer = EXCLUDED.area_of_border_buffer,
    nodes_per_area_shrunk_grids = EXCLUDED.nodes_per_area_shrunk_grids,
    nodes_per_area_border_buffer = EXCLUDED.nodes_per_area_border_buffer;