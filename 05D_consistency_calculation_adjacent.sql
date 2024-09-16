-- Run this part multiple times until it alls gets done
WITH proj_ids AS (
    SELECT DISTINCT gc.project_id AS ids
    FROM public.geometry_consistency gc
    WHERE NOT EXISTS (
		SELECT gca.project_id
		FROM geometry_consistency_adjacent gca
		WHERE gca.project_id = gc.project_id
		LIMIT 1
	  )
	LIMIT 5
)
INSERT INTO geometry_consistency_adjacent (project_id, task_id, neighbouring_average_vertices_original, neighbouring_average_vertices_simplified, neighbouring_average_simplified_area_covered_from_original, neighbouring_number_of_buildings, number_of_neighbouring_tasks, neighbouring_tasks_area, tolerance_used)
SELECT project_id, task_id,
		average_vertices_original AS neighbouring_average_vertices_original,
		average_vertices_simplified AS neighbouring_average_vertices_simplified,
		average_simplified_area_covered_from_original,
		number_of_buildings AS neighbouring_number_of_buildings,
		number_of_tasks AS number_of_neighbouring_tasks,
		task_area AS neighbouring_tasks_area, tolerance_used
FROM get_ratio_simplified_buildings_multiple_adjacent((SELECT array_agg(ids) FROM proj_ids))
ON CONFLICT (project_id, task_id, tolerance_used)
DO UPDATE SET 
	neighbouring_average_vertices_original = EXCLUDED.neighbouring_average_vertices_original,
	neighbouring_average_vertices_simplified = EXCLUDED.neighbouring_average_vertices_simplified,
	neighbouring_average_simplified_area_covered_from_original = EXCLUDED.neighbouring_average_simplified_area_covered_from_original,
	neighbouring_number_of_buildings = EXCLUDED.neighbouring_number_of_buildings,
	number_of_neighbouring_tasks = EXCLUDED.number_of_neighbouring_tasks,
	neighbouring_tasks_area = EXCLUDED.neighbouring_tasks_area;
