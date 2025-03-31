-- Select the mockup grids to cover the desired percentage
DROP FUNCTION IF EXISTS select_random_mockup_grids;
CREATE OR REPLACE FUNCTION select_random_mockup_grids(percentage_covered DOUBLE PRECISION, project_id INTEGER)
RETURNS TABLE(taskid INTEGER, geom GEOMETRY) 
AS $$
DECLARE
    target_total_area DOUBLE PRECISION;
BEGIN
    CALL raise_notice('Project ' || project_id || ' | Percentage ' || percentage_covered);

    -- Calculate the total area to be covered per taskid
    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_target_areas') THEN
        DROP TABLE IF EXISTS temp_target_areas;
    END IF;
    CREATE TEMP TABLE temp_target_areas AS
    SELECT g.taskid, (ST_Area(g.geom_utm) / 100.0 * percentage_covered) AS target_area
    FROM grids g
    WHERE g.project_id = select_random_mockup_grids.project_id;

    -- Use a parallelizable query to select random geometries
    RETURN QUERY
    WITH random_mockup_grids AS (
        SELECT mg.taskid, mg.geom, ST_Area(mg.geom) AS area
        FROM mockup_grids mg
        WHERE mg.project_id = select_random_mockup_grids.project_id
        ORDER BY random()
    ),
    aggregated AS (
        SELECT rmg.taskid, rmg.geom, SUM(rmg.area) OVER (PARTITION BY rmg.taskid ORDER BY random()) AS accumulated_area
        FROM random_mockup_grids rmg
        JOIN temp_target_areas tta ON rmg.taskid = tta.taskid
    ),
    selected AS (
        -- Select all rows that do not exceed the target
        SELECT a.*, tta.target_area FROM aggregated a
        JOIN temp_target_areas tta ON a.taskid = tta.taskid
        WHERE a.accumulated_area <= tta.target_area

        UNION ALL

        -- Add exactly one extra row that first exceeds the target
        SELECT * FROM (SELECT a.*, tta.target_area FROM aggregated a
        JOIN temp_target_areas tta ON a.taskid = tta.taskid
        WHERE a.accumulated_area > tta.target_area
        ORDER BY accumulated_area ASC
        LIMIT 1) b
    ),
    final AS (
        -- Clip the extra row to fit the target area
        SELECT s.taskid,
            CASE 
                WHEN s.accumulated_area > s.target_area AND ST_Area(s.geom) > 0 THEN 
                    shrink_geometry(s.geom, s.accumulated_area - s.target_area, true)
                ELSE s.geom
            END AS geom
        FROM selected s
    )
    SELECT * FROM final;

    -- Cleanup
    -- DROP TABLE IF EXISTS temp_target_areas;
END $$ LANGUAGE plpgsql PARALLEL SAFE;


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

    IF (SELECT COUNT(*) FROM temp_project_ids) = 0 THEN
        CALL raise_notice('All projects have been processed');
        RETURN;
    END IF;

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
