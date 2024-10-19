-- CALCULATE NON-CONNECTING NODES
-- Run this part multiple times until it alls gets done
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
        WHERE typename = 'ROADS'
        AND project_has_fully_adjacent_cells(proj_id)
        AND NOT EXISTS (
            SELECT nn.project_id
            FROM nonconnecting_nodes nn
            WHERE nn.project_id = proj_id
            LIMIT 1
          )
        --- LIMIT 100
    ) subquery;
    
    -- Iterate over each project_id
    FOREACH current_project_id IN ARRAY project_ids LOOP
        RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
        INSERT INTO nonconnecting_nodes (project_id, geom, point_type)
        SELECT current_project_id AS project_id, gncsen.node AS geom, gncsen.point_type
        FROM get_nonconnecting_start_end_nodes_in_utm(current_project_id) AS gncsen;
    END LOOP;
END $$;