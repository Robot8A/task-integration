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
            SELECT bu.project_id
            FROM buildings_utm bu
            WHERE bu.project_id = proj_id
            LIMIT 1
          )
        --- LIMIT 100
    ) subquery;

	-- Iterate over each project_id
    FOREACH current_project_id IN ARRAY project_ids LOOP
		RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
		INSERT INTO buildings_utm (osm_id, geom, project_id)
		SELECT osm_id, geom, current_project_id AS project_id
		FROM transform_buildings_to_utm(current_project_id);
	END LOOP;
END $$;