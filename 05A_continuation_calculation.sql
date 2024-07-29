CREATE TABLE IF NOT EXISTS continuation (
    project_id INT,
    grid_type TEXT,
    shrink_distance DOUBLE PRECISION,
    nodes_in_shrunk_grids BIGINT,
    nodes_in_border_buffer BIGINT,
    area_of_shrunk_grids DOUBLE PRECISION,
    area_of_border_buffer DOUBLE PRECISION,
    nodes_per_area_shrunk_grids DOUBLE PRECISION,
    nodes_per_area_border_buffer DOUBLE PRECISION,
    PRIMARY KEY (project_id, grid_type, shrink_distance)
);

WITH proj_ids AS (
	SELECT proj_id AS ids
	FROM public.mapping_types
	WHERE typename = 'ROADS'
    AND project_has_fully_adjacent_cells(proj_id)
    OFFSET 0
	LIMIT 10
)
INSERT INTO continuation (project_id, grid_type, shrink_distance, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer)
SELECT project_id, grid_type, shrink_distance, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer
FROM continuation(
	(SELECT array_agg(ids) FROM proj_ids),
	ARRAY[5.0, 10.0, 15.0],
    ARRAY['ORIGINAL', 'MOCKUP']
)
ON CONFLICT (project_id, grid_type, shrink_distance) 
DO UPDATE SET 
    nodes_in_shrunk_grids = EXCLUDED.nodes_in_shrunk_grids,
    nodes_in_border_buffer = EXCLUDED.nodes_in_border_buffer,
    area_of_shrunk_grids = EXCLUDED.area_of_shrunk_grids,
    area_of_border_buffer = EXCLUDED.area_of_border_buffer,
    nodes_per_area_shrunk_grids = EXCLUDED.nodes_per_area_shrunk_grids,
    nodes_per_area_border_buffer = EXCLUDED.nodes_per_area_border_buffer;