-- CREATE MOCKUP GRIDS
-- Run this part multiple times until it alls gets done
DO $$ 
DECLARE
    current_project_id INT;
    project_ids INT[];
BEGIN
    -- Get project IDs into an array
    SELECT array_agg(ids) INTO project_ids
    FROM (
        SELECT proj_id AS ids
        FROM public.mapping_types
        WHERE (typename = 'ROADS' OR typename = 'BUILDINGS')
        AND project_has_fully_adjacent_cells(proj_id)
        AND NOT EXISTS (
		    SELECT mg.project_id
		    FROM mockup_grids mg
		    WHERE mg.project_id = proj_id
			LIMIT 1
		  )
        LIMIT 100
    ) subquery;
    
    -- Iterate over each project_id
    FOREACH current_project_id IN ARRAY project_ids LOOP
        RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
        INSERT INTO mockup_grids (project_id, geom)
        SELECT current_project_id AS project_id, geom
        FROM generate_mockup_grid(current_project_id);
    END LOOP;
END $$;

-- CREATE MOCKUP POLYGON GRIDS
-- Run this part multiple times until it alls gets done
DO $$
DECLARE
    current_project_id INT;
    project_ids INT[];
    percentage_covered DOUBLE PRECISION := 50;
BEGIN
    -- Get project IDs into an array
    SELECT array_agg(ids) INTO project_ids
    FROM (
        SELECT proj_id AS ids
        FROM public.mapping_types
        WHERE (typename = 'ROADS' OR typename = 'BUILDINGS')
        AND project_has_fully_adjacent_cells(proj_id)
        AND NOT EXISTS (
            SELECT mpg.project_id
            FROM mockup_polygon_grids mpg
            WHERE mpg.project_id = proj_id
            LIMIT 1
          )
        LIMIT 100
    ) subquery;
    
    -- Iterate over each project_id
    FOREACH current_project_id IN ARRAY project_ids LOOP
        RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
        INSERT INTO mockup_polygon_grids (project_id, geom, percentage_covered)
        SELECT current_project_id AS project_id, geom, percentage_covered
        FROM generate_mockup_polygon_grid(current_project_id, 10);
    END LOOP;
END $$;