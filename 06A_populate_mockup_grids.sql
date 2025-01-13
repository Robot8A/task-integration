-- POPULATE MOCKUP POLYGON GRIDS
DO $$
DECLARE
    current_project_id INT;
    project_ids INT[];
    percentages DOUBLE PRECISION[] := ARRAY[5.0, 10.0, 15.0];
    perc_covered DOUBLE PRECISION;
BEGIN
    FOREACH perc_covered IN ARRAY percentages LOOP
        RAISE NOTICE '--- Percentage Covered: % ---', perc_covered;
    
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
    END LOOP;
END $$;

-- POPULATE MOCKUP POLYGON GRIDS
-- CREATE TABLE IF NOT EXISTS percentages_covered(percentage_covered DOUBLE PRECISION);
-- INSERT INTO percentages_covered (percentage_covered) VALUES (5.0), (10.0), (15.0);

-- CREATE TEMP TABLE temp_project_ids AS
-- SELECT proj_id
-- FROM selected_projects;

-- CREATE TEMP TABLE temp_percentages AS
-- SELECT DISTINCT percentage_covered
-- FROM percentages_covered;

-- CREATE TABLE projects_percentages AS
-- SELECT pi.proj_id, pc.percentage_covered
-- FROM temp_project_ids pi
-- CROSS JOIN temp_percentages pc;

-- DROP TABLE IF EXISTS temp_project_ids;
-- DROP TABLE IF EXISTS temp_percentages;

-- INSERT INTO mockup_polygon_grids (project_id, taskid, geom, percentage_covered)
-- SELECT pp.proj_id AS project_id, gmpg.taskid, gmpg.geom, pp.percentage_covered AS perc_covered
-- FROM projects_percentages AS pp
-- JOIN LATERAL generate_mockup_polygon_grid(pp.proj_id, pp.percentage_covered) AS gmpg ON true;

-- DROP TABLE IF EXISTS percentages_covered;
-- DROP TABLE IF EXISTS projects_percentages;
