-- CALCULATE DUPLICATED BUILDINGS
DO $$
DECLARE
    current_project_id INT;
BEGIN
    RAISE NOTICE '-------------------------------------------';
    RAISE NOTICE '-- 09B_cont_dup_duplicated_buildings.sql --';
    RAISE NOTICE '-------------------------------------------';

    -- Create the table if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'duplicated_buildings') THEN
        CREATE TABLE IF NOT EXISTS duplicated_buildings (
            building_a_id INT,
            building_b_id INT,
            intersection_geom GEOMETRY,
            intersection_centroid GEOMETRY,
            project_id INT
        );
    END IF;

    -- Get the selected projects
	CALL raise_notice('Selecting projects');
    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_project_ids') THEN
        DROP TABLE temp_project_ids;
    END IF;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT proj_id
	FROM selected_projects
    WHERE indicator_cont_dup = 8
    AND typename = 'BUILDINGS'
	ORDER BY proj_id
	--;
    --LIMIT (SELECT COUNT(*) * 0.0025 FROM selected_projects);
    LIMIT 1;
	CALL raise_notice('Projects selected');

    -- Iterate over each project_id
    FOREACH current_project_id IN ARRAY (SELECT array_agg(proj_id) FROM temp_project_ids) LOOP
        RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
        INSERT INTO duplicated_buildings (building_a_id, building_b_id, intersection_geom, intersection_centroid, project_id)
		SELECT building_a_id, building_b_id, intersection_geom, ST_Centroid(intersection_geom) AS intersection_centroid, current_project_id AS project_id
		FROM get_duplicated_buildings(current_project_id);
    END LOOP;

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cont_dup = indicator_cont_dup + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
    AND typename = 'BUILDINGS';

    -- Cleanup
    DROP TABLE IF EXISTS temp_project_ids;
END $$;
