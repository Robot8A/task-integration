DO $$ 
DECLARE
    distances FLOAT[];
    grid_types TEXT[];
BEGIN
    distances := ARRAY[5.0::FLOAT, 10.0::FLOAT, 15.0::FLOAT];
    grid_types := ARRAY['MOCKUP-POLY'::TEXT, 'ORIGINAL'::TEXT];
    
    WITH proj_ids AS (
        SELECT proj_id AS ids
        FROM public.mapping_types
        WHERE typename = 'ROADS'
        AND project_has_fully_adjacent_cells(proj_id)
        AND NOT EXISTS (
            SELECT co.project_id
            FROM continuation co
            WHERE co.project_id = proj_id
            AND grid_type = ANY(grid_types)
            LIMIT 1
            )
        --- LIMIT 200 --- Uncomment this line to limit the number of projects to process and run batch by batch. Afterwards, it is needed to run the code multiple times to process all projects.
    )
    INSERT INTO continuation (project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer)
    SELECT project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer
    FROM continuation(
        (SELECT array_agg(ids) FROM proj_ids),
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
END $$;