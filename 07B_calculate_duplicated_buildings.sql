CREATE TABLE IF NOT EXISTS duplicated_buildings (
    building_a_id INT,
	building_b_id INT,
	intersection_geom GEOMETRY,
	intersection_centroid GEOMETRY,
	project_id INT
);

DO $$
DECLARE
    current_project_id INT;
    project_ids INT[];
BEGIN
    -- Get project IDs into an array
    SELECT array_agg(ids) INTO project_ids
    FROM (
        SELECT DISTINCT proj_id AS ids
        FROM public.mapping_types
        WHERE typename = 'BUILDINGS'
        AND project_has_fully_adjacent_cells(proj_id)
        AND NOT EXISTS (
            SELECT db.project_id
            FROM duplicated_buildings db
            WHERE db.project_id = proj_id
            LIMIT 1
          )
        --- LIMIT 100
    ) subquery;

	-- Iterate over each project_id
    FOREACH current_project_id IN ARRAY project_ids LOOP
		RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
		INSERT INTO duplicated_buildings (building_a_id, building_b_id, intersection_geom, intersection_centroid, project_id)
		SELECT building_a_id, building_b_id, intersection_geom, ST_Centroid(intersection_geom) AS intersection_centroid, current_project_id AS project_id
		FROM get_duplicated_buildings(current_project_id);
	END LOOP;
END $$;