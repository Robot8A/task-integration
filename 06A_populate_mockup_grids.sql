-- POPULATE MOCKUP POLYGON GRIDS
-- Run this part multiple times until it alls gets done
DO $$
DECLARE
    current_project_id INT;
    project_ids INT[];
    perc_covered DOUBLE PRECISION := 15.0;
BEGIN
    -- Get project IDs into an array
    SELECT array_agg(ids) INTO project_ids
    FROM (
        SELECT DISTINCT proj_id AS ids
        FROM selected_projects
        WHERE NOT EXISTS (
            SELECT mpg.project_id
            FROM mockup_polygon_grids mpg
            WHERE mpg.project_id = proj_id
            AND mpg.percentage_covered = perc_covered
            LIMIT 1
          )
        --LIMIT 100
    ) subquery;
    
    -- Iterate over each project_id
    IF project_ids IS NOT NULL THEN
        FOREACH current_project_id IN ARRAY project_ids LOOP
            RAISE NOTICE 'TIME % | Project ID: %', clock_timestamp(), current_project_id;
            INSERT INTO mockup_polygon_grids (project_id, taskid, geom, percentage_covered)
            SELECT current_project_id AS project_id, gmpg.taskid, gmpg.geom, perc_covered
            FROM generate_mockup_polygon_grid(current_project_id, perc_covered) AS gmpg;
        END LOOP;
    END IF;
END $$;