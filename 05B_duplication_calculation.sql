CREATE TABLE IF NOT EXISTS duplicated_buildings (
    building_a_id INT,
	building_b_id INT,
	intersection_geom GEOMETRY,
	project_id INT
);

WITH proj_ids AS (
	SELECT proj_id AS ids
	FROM public.mapping_types
	WHERE typename = 'BUILDINGS'
    AND project_has_fully_adjacent_cells(proj_id)
    OFFSET 0
	LIMIT 10
)
FOR i IN 1..array_length(project_ids, 1) LOOP
    	current_project_id := proj_ids[i];

		INSERT INTO duplicated_buildings (building_a_id, building_b_id, intersection_geom, project_id)
		SELECT building_a_id, building_b_id, intersection_geom, current_project_id AS project_id
		FROM get_duplicated_buildings(current_project_id);
