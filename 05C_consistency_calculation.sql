CREATE TABLE IF NOT EXISTS geometry_consistency (
    project_id INT,
    task_id INT,
    average_vertices_original FLOAT,
    average_vertices_simplified FLOAT,
    average_simplified_area_covered_from_original FLOAT,
    number_of_buildings INT,
    task_area FLOAT,
    tolerance_used FLOAT,
    PRIMARY KEY (project_id, task_id, tolerance_used)
);

WITH proj_ids AS (
    SELECT proj_id AS ids
    FROM public.mapping_types
    WHERE typename = 'BUILDINGS'
    AND project_has_fully_adjacent_cells(proj_id)
    OFFSET 0
	LIMIT 5
)
INSERT INTO geometry_consistency (project_id, task_id, average_vertices_original, average_vertices_simplified, average_simplified_area_covered_from_original, number_of_buildings, task_area, tolerance_used)
SELECT project_id, task_id, average_vertices_original, average_vertices_simplified, average_simplified_area_covered_from_original, number_of_buildings, task_area, tolerance_used
FROM get_ratio_simplified_buildings_multiple((SELECT array_agg(ids) FROM proj_ids));
ON CONFLICT (project_id, task_id, tolerance_used)
DO UPDATE SET 
    average_vertices_original = EXCLUDED.average_vertices_original,
    average_vertices_simplified = EXCLUDED.average_vertices_simplified,
    average_simplified_area_covered_from_original = EXCLUDED.average_simplified_area_covered_from_original,
    number_of_buildings = EXCLUDED.number_of_buildings,
    task_area = EXCLUDED.task_area;
