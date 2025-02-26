-- Select the mockup grids to cover the desired percentage
DROP FUNCTION IF EXISTS select_random_mockup_grids;
CREATE OR REPLACE FUNCTION select_random_mockup_grids(percentage_covered DOUBLE PRECISION, project_id INTEGER)
RETURNS TABLE(taskid INTEGER, geom GEOMETRY) AS $$
DECLARE
	task RECORD;
	mockup_polygon RECORD;
    target_total_area DOUBLE PRECISION;
    accumulated_area DOUBLE PRECISION := 0.0;
    remaining_area DOUBLE PRECISION;
	dilate_tolerance DOUBLE PRECISION;
	dilate_tolerance_factor_of_area DOUBLE PRECISION := 20;
	dilate_guess DOUBLE PRECISION;
	dilate_guess_factor_of_area DOUBLE PRECISION := 50;
	dilate_safety INTEGER := 1000000000;
BEGIN
    CALL raise_notice('Project ' || project_id || ' | Percentage ' || percentage_covered);

    -- Select all distinct taskids for the project
    FOR task IN SELECT * FROM grids g WHERE g.project_id = select_random_mockup_grids.project_id
    LOOP
        taskid := task.taskid;

        -- Calculate the target total area
        SELECT (ST_Area(task.geom_utm) / 100.0 * percentage_covered) INTO target_total_area;

        -- Create a temporary table for the geometries
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'temp_mockup_grids') THEN
            DROP TABLE temp_mockup_grids;
        END IF;
        CREATE TEMP TABLE temp_mockup_grids AS
        SELECT mg.geom, ST_Area(mg.geom) AS area
        FROM mockup_grids mg
        WHERE mg.project_id = select_random_mockup_grids.project_id AND mg.taskid = task.taskid;

        accumulated_area := 0.0;
        -- Iterate over the rows in the temporary table
        FOR mockup_polygon IN
            SELECT tmg.geom, tmg.area FROM temp_mockup_grids tmg
            ORDER BY random() -- Shuffle the rows
        LOOP
            -- Add the area of the current geometry to the accumulated area
            accumulated_area := accumulated_area + mockup_polygon.area;

            -- If we went over the target total area, clip the geometry to cover the remaining area
            IF accumulated_area > target_total_area THEN
                -- Set tolerance and guess for ST_Dilate
                dilate_tolerance := mockup_polygon.area / dilate_tolerance_factor_of_area;
                dilate_guess := mockup_polygon.area / dilate_guess_factor_of_area;

                -- Clip the geometry to cover the remaining area
                remaining_area := target_total_area - (accumulated_area - mockup_polygon.area);
                mockup_polygon.geom := ST_Dilate(
                    mockup_polygon.geom,
                    remaining_area / mockup_polygon.area,
                    tol => dilate_tolerance,
                    guess => dilate_guess,
                    safety => dilate_safety
                );

                -- Handle ST_Dilate failure
                IF mockup_polygon.geom IS NULL THEN
                    RAISE NOTICE 'Failed to clip geometry, returning original geometry';
                END IF;

                -- Set accumulated area to target total area
                accumulated_area := target_total_area;
            END IF;

            -- Return the selected geometry
            geom := mockup_polygon.geom;
            RETURN NEXT;

            -- Stop if target area is covered
            EXIT WHEN accumulated_area >= target_total_area;
        END LOOP;
    END LOOP;
    DROP TABLE IF EXISTS temp_mockup_grids;
    RETURN;
END $$ LANGUAGE plpgsql;

-- POPULATE MOCKUP POLYGON GRIDS
DO $$
DECLARE
    grid_size_factor FLOAT := 25;
BEGIN
    SET min_parallel_index_scan_size = 100;
    SET min_parallel_table_scan_size = 100;
    SET parallel_setup_cost = 1;
    SET parallel_tuple_cost = 0.1;
    SET max_parallel_workers = 10;
    SET max_parallel_workers_per_gather = 10;

    -- Get 10% of the selected projects
	CALL raise_notice('Selecting projects');
	DROP TABLE IF EXISTS temp_project_ids;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT DISTINCT(proj_id)
	FROM selected_projects
	WHERE indicator_cont_dup = 7
	ORDER BY proj_id
	--LIMIT (SELECT COUNT(*) * 0.0025 FROM selected_projects);
	LIMIT 10;
	CALL raise_notice('Projects selected');

    -- Populate mockup grids
    CALL raise_notice('Populating mockup grids');

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'mockup_grids') THEN
        CREATE TABLE mockup_grids (project_id INTEGER, taskid INTEGER, geom GEOMETRY);
    END IF;

    INSERT INTO mockup_grids (project_id, taskid, geom)
    SELECT g.project_id, g.taskid, ST_Intersection(g.geom_utm, (ST_SquareGrid(sqrt(ST_Area(g.geom_utm)) / grid_size_factor, g.geom_utm)).geom) AS geom
    FROM grids g
    JOIN temp_project_ids tpi ON g.project_id = tpi.proj_id;

    CALL raise_notice('Mockup grids populated');

    -- Create a table to store the selected mockup grids
	CALL raise_notice('Selecting random mockup grids');

	IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'mockup_selected_grids') THEN
        CREATE TABLE mockup_selected_grids (proj_id INTEGER, taskid INTEGER, geom GEOMETRY, percentage_covered DOUBLE PRECISION);
    END IF;

    INSERT INTO mockup_selected_grids (proj_id, taskid, geom, percentage_covered)
    SELECT tpi.proj_id, srmg.taskid, srmg.geom, 5.0 AS percentage_covered
    FROM temp_project_ids tpi
    CROSS JOIN LATERAL (SELECT * FROM select_random_mockup_grids(5.0, tpi.proj_id)) srmg
    UNION ALL
    SELECT tpi.proj_id, srmg.taskid, srmg.geom, 10.0 AS percentage_covered
    FROM temp_project_ids tpi
    CROSS JOIN LATERAL (SELECT * FROM select_random_mockup_grids(10.0, tpi.proj_id)) srmg
    UNION ALL
    SELECT tpi.proj_id, srmg.taskid, srmg.geom, 15.0 AS percentage_covered
    FROM temp_project_ids tpi
    CROSS JOIN LATERAL (SELECT * FROM select_random_mockup_grids(15.0, tpi.proj_id)) srmg;

    CALL raise_notice('Random mockup grids selected');

    -- Update the selected projects to indicate that they have been processed
	UPDATE selected_projects
    SET indicator_cont_dup = indicator_cont_dup + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids);

    -- Cleanup
    DELETE FROM mockup_grids mg WHERE ST_IsEmpty(mg.geom);
    DROP TABLE IF EXISTS temp_project_ids;
END $$;
