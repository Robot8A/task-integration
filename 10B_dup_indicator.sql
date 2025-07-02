-- CALCULATE THE DUPLICATION INDICATOR
DO $$ 
DECLARE
    distances DOUBLE PRECISION[];
    grid_types TEXT[] := ARRAY['MOCKUP'::TEXT, 'ORIGINAL'::TEXT];
    total_projects INT;
    processed_projects INT := 0;
    proj_ids INT[]; -- Array to store project IDs
    current_project_id INT; -- Variable to store individual project ID during the loop
BEGIN
    RAISE NOTICE '---------------------------';
    RAISE NOTICE '-- 10B_dup_indicator.sql --';
    RAISE NOTICE '---------------------------';

    -- Create the table if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'duplication') THEN
        CREATE TABLE duplication (
            project_id INT,
            grid_type TEXT,
            shrink_distance DOUBLE PRECISION,
            shrink_type TEXT,
            nodes_in_shrunk_grids INT,
            nodes_in_border_buffer INT,
            area_of_shrunk_grids DOUBLE PRECISION,
            area_of_border_buffer DOUBLE PRECISION,
            nodes_per_area_shrunk_grids DOUBLE PRECISION,
            nodes_per_area_border_buffer DOUBLE PRECISION
        );
        ALTER TABLE duplication ADD PRIMARY KEY (project_id, grid_type, shrink_distance, shrink_type);
    END IF;

    -- Get the selected projects
    CALL raise_notice('Selecting projects');
    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_project_ids') THEN
        DROP TABLE temp_project_ids;
    END IF;
    CREATE TEMP TABLE temp_project_ids AS
    SELECT proj_id
    FROM selected_projects
    WHERE indicator_cont_dup = 9
    AND typename = 'BUILDINGS'
    ORDER BY proj_id
    ;
    CALL raise_notice('Projects selected');

    -- Get the total number of projects
    total_projects := (SELECT COUNT(*) FROM temp_project_ids);

    -- Loop through the projects, and calculate duplication indicators
    FOREACH current_project_id IN ARRAY (SELECT array_agg(proj_id) FROM temp_project_ids)
    LOOP
        FOREACH grid_type in ARRAY grid_types
        LOOP
            IF grid_type = 'MOCKUP' THEN
                distances = ARRAY[5.0::DOUBLE PRECISION, 10.0::DOUBLE PRECISION, 15.0::DOUBLE PRECISION];
            ELSIF grid_type = 'ORIGINAL' THEN
                distances = ARRAY(SELECT i::DOUBLE PRECISION FROM generate_series(0, 100, 5) AS i);
            ELSE 
                RAISE EXCEPTION 'Unknown grid type: %', grid_type;
            END IF;
            INSERT INTO duplication (project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer)
                SELECT current_project_id as project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer
                FROM duplication(
                    ARRAY[current_project_id],
                    distances,
                    ARRAY[grid_type],
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
        END LOOP;

        processed_projects := processed_projects + 1;

        RAISE NOTICE '--------------------------------------------------';
        RAISE NOTICE 'Processed % of % projects (% %%)', processed_projects, total_projects, (processed_projects::FLOAT / total_projects::FLOAT) * 100;
        RAISE NOTICE '--------------------------------------------------';
    END LOOP;

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cont_dup = indicator_cont_dup + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
    AND typename = 'BUILDINGS';

    CALL raise_notice('Cleanup');

    -- Delete the rows for the nonconnecting nodes table for the selected projects
    DELETE FROM duplicated_buildings
    WHERE project_id IN (SELECT proj_id FROM temp_project_ids);

    -- Delete the rows for the mockup grids and mockup selected grids tables for the selected projects where cont and dup indicators have already been calculated
    IF 'MOCKUP' = ANY(grid_types) THEN
        DELETE FROM mockup_grids
        WHERE project_id IN (
            SELECT proj_id 
            FROM selected_projects
            GROUP BY proj_id
            HAVING MIN(indicator_cont_dup) = 10
        );
        DELETE FROM mockup_selected_grids
        WHERE proj_id IN (
            SELECT proj_id 
            FROM selected_projects
            GROUP BY proj_id
            HAVING MIN(indicator_cont_dup) = 10
        );
    END IF;

    -- Delete the temporary table
    DROP TABLE temp_project_ids;

    CALL raise_notice('Done');
END $$;