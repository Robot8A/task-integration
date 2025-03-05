-- CALCULATE NON-CONNECTING NODES
DO $$
DECLARE
    current_project_id INT;
BEGIN
    RAISE NOTICE '------------------------------------------';
    RAISE NOTICE '-- 09A_cont_dup_nonconnecting_nodes.sql --';
    RAISE NOTICE '------------------------------------------';

    -- Create the table if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'nonconnecting_nodes') THEN
        CREATE TABLE IF NOT EXISTS nonconnecting_nodes (
            project_id INT,
            geom GEOMETRY,
            point_type VARCHAR(255)
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
    AND typename = 'ROADS'
	ORDER BY proj_id
	--;
    --LIMIT (SELECT COUNT(*) * 0.0025 FROM selected_projects);
	LIMIT 10;
	CALL raise_notice('Projects selected');

    -- Iterate over each project_id
    FOREACH current_project_id IN ARRAY (SELECT array_agg(proj_id) FROM temp_project_ids) LOOP
        RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
        INSERT INTO nonconnecting_nodes (project_id, geom, point_type)
        SELECT current_project_id AS project_id, gncsen.node AS geom, gncsen.point_type
        FROM get_nonconnecting_start_end_nodes_in_utm(current_project_id) AS gncsen;
    END LOOP;

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cont_dup = indicator_cont_dup + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
    AND typename = 'ROADS';

    -- Cleanup
    DROP TABLE IF EXISTS temp_project_ids;
END $$;
