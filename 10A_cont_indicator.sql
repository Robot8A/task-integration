-- CALCULATE THE CONTINUATION INDICATOR
DO $$ 
DECLARE
    distances FLOAT[] := ARRAY[5.0::FLOAT, 10.0::FLOAT, 15.0::FLOAT];
    grid_types TEXT[] := ARRAY['MOCKUP'::TEXT, 'ORIGINAL'::TEXT];
    total_projects INT;
    processed_projects INT := 0;
    proj_ids INT[]; -- Array to store project IDs
    current_project_id INT; -- Variable to store individual project ID during the loop
BEGIN
    RAISE NOTICE '----------------------------';
    RAISE NOTICE '-- 10A_cont_indicator.sql --';
    RAISE NOTICE '----------------------------';

    -- Create the table if it doesn't exist
    CREATE TABLE IF NOT EXISTS continuation (
        project_id INT,
        grid_type TEXT,
        shrink_distance FLOAT,
        shrink_type TEXT,
        nodes_in_shrunk_grids INT,
        nodes_in_border_buffer INT,
        area_of_shrunk_grids FLOAT,
        area_of_border_buffer FLOAT,
        nodes_per_area_shrunk_grids FLOAT,
        nodes_per_area_border_buffer FLOAT
    );
    ALTER TABLE continuation ADD PRIMARY KEY (project_id, grid_type, shrink_distance, shrink_type);
    
    -- Get the selected projects
	CALL raise_notice('Selecting projects');
    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_project_ids') THEN
        DROP TABLE temp_project_ids;
    END IF;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT proj_id
	FROM selected_projects
    WHERE indicator_cont_dup = 9
    AND typename = 'ROADS'
	ORDER BY proj_id
	;
    --LIMIT (SELECT COUNT(*) * 0.0025 FROM selected_projects);
	--LIMIT 1;
	CALL raise_notice('Projects selected');

    -- Get the total number of projects
    total_projects := (SELECT COUNT(*) FROM temp_project_ids);

    -- Loop through the projects, and calculate continuation indicators
    FOREACH current_project_id IN ARRAY (SELECT array_agg(proj_id) FROM temp_project_ids)
    LOOP
        INSERT INTO continuation (project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer)
            SELECT current_project_id as project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer
            FROM continuation(
                ARRAY[current_project_id],
                distances,
                grid_types,
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

        processed_projects := processed_projects + 1;

        RAISE NOTICE '--------------------------------------------------';
        RAISE NOTICE 'Processed % of % projects (% %%)', processed_projects, total_projects, (processed_projects::FLOAT / total_projects::FLOAT) * 100;
        RAISE NOTICE '--------------------------------------------------';
    END LOOP;

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cont_dup = indicator_cont_dup + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
    AND typename = 'ROADS';
END $$;