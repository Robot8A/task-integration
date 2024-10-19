DO $$ 
DECLARE
    distances FLOAT[];
    grid_types TEXT[];
    total_projects INT;
    processed_projects INT := 0;
    proj_ids INT[]; -- Array to store project IDs
    current_project_id INT; -- Variable to store individual project ID during the loop
BEGIN
    distances := ARRAY[5.0::FLOAT, 10.0::FLOAT, 15.0::FLOAT];
    --- distances := array(SELECT generate_series(0.0, 25.0));
    grid_types := ARRAY['MOCKUP-POLY'::TEXT, 'ORIGINAL'::TEXT];
    
    SELECT ARRAY (
        SELECT distinct(nn.project_id) AS ids
        FROM nonconnecting_nodes AS nn
        WHERE NOT EXISTS (
            SELECT co.project_id
            FROM continuation co
            WHERE co.project_id = nn.project_id
            AND grid_type = ANY(grid_types)
            LIMIT 1
            )
        --- LIMIT 200 --- Uncomment this line to limit the number of projects to process and run batch by batch. Afterwards, it is needed to run the code multiple times to process all projects.
    ) INTO proj_ids;

    -- Get the total number of projects
    total_projects := array_length(proj_ids, 1);

    -- Loop through the projects, and calculate continuation indicators
    FOREACH current_project_id IN ARRAY proj_ids
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
END $$;