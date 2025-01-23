-- Select the mockup grids to cover the desired percentage
DROP FUNCTION IF EXISTS select_random_mockup_grids;
CREATE OR REPLACE FUNCTION select_random_mockup_grids(percentage_covered DOUBLE PRECISION, project_id INTEGER)
RETURNS TABLE(taskid INTEGER, geom GEOMETRY) AS $$
DECLARE
	task RECORD;
	mockup_polygon RECORD;
    target_total_area NUMERIC;
    accumulated_area NUMERIC := 0;
    remaining_area NUMERIC;
	dilate_tolerance DOUBLE PRECISION;
	dilate_tolerance_factor_of_area DOUBLE PRECISION := 20;
	dilate_guess DOUBLE PRECISION;
	dilate_guess_factor_of_area DOUBLE PRECISION := 50;
	dilate_safety INTEGER := 1000000000;
BEGIN
	-- Select all distinct taskids for the project
	FOR task IN SELECT * FROM grids g WHERE g.project_id = select_random_mockup_grids.project_id
	LOOP
		accumulated_area := 0;
		taskid := task.taskid;

		-- Calculate the target total area
		SELECT ST_Area(task.geom) * percentage_covered INTO target_total_area;

		-- Create a temporary table for the geometries
		DROP TABLE IF EXISTS temp_mockup_grids;
		CREATE TEMP TABLE temp_mockup_grids AS
		SELECT mg.geom, ST_Area(mg.geom) AS area
		FROM mockup_grids mg
		WHERE mg.project_id = select_random_mockup_grids.project_id AND mg.taskid = task.taskid
		ORDER BY random(); -- Shuffle the rows

		-- Iterate over the rows in the temporary table
		FOR mockup_polygon IN
			SELECT tmg.geom, tmg.area FROM temp_mockup_grids tmg
		LOOP
			accumulated_area := accumulated_area + mockup_polygon.area;

			-- Set tolerance and guess for ST_Dilate
			dilate_tolerance := mockup_polygon.area / dilate_tolerance_factor_of_area;
			dilate_guess := mockup_polygon.area / dilate_guess_factor_of_area;

			-- Check if we need to clip the geometry
			IF accumulated_area > target_total_area THEN
				-- remaining_area := target_total_area - (accumulated_area - mockup_polygon.area);
				-- mockup_polygon.geom := ST_Dilate(
				-- 	mockup_polygon.geom,
				-- 	remaining_area / mockup_polygon.area,
				-- 	tol => dilate_tolerance,
				-- 	guess => dilate_guess,
				-- 	safety => dilate_safety
				-- );

				-- -- Handle failure to dilate
				-- IF mockup_polygon.geom IS NULL THEN
				-- 	RAISE NOTICE 'Failed to dilate geometry, returning original geometry';
				-- END IF;

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
END $$ LANGUAGE plpgsql;


-- Run multiple times until all projects have been processed
DO $$
BEGIN
	-- Get 10% of the selected projects
	CALL raise_notice('Selecting projects');
	DROP TABLE IF EXISTS temp_project_ids;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT proj_id, typename
	FROM selected_projects
	WHERE indicator_cont_dup = 7
	ORDER BY proj_id
	--LIMIT (SELECT COUNT(*) * 0.0025 FROM selected_projects);
	LIMIT 1;
	CALL raise_notice('Projects selected');

	-- Populate mockup grids
	SET min_parallel_index_scan_size = 100;
	SET min_parallel_table_scan_size = 100;
	SET parallel_setup_cost = 1;
	SET parallel_tuple_cost = 0.1;
	SET max_parallel_workers = 10;
	SET max_parallel_workers_per_gather = 10;


	CALL raise_notice('Populating mockup grids');
	DROP TABLE IF EXISTS mockup_grids;
	CREATE TEMP TABLE mockup_grids AS
	SELECT g.project_id, g.taskid, ST_Intersection(g.geom_utm, (ST_SquareGrid(sqrt(ST_Area(g.geom_utm)) / 50, g.geom_utm)).geom) AS geom
	FROM grids g
	JOIN temp_project_ids tpi ON g.project_id = tpi.proj_id;
	CALL raise_notice('Mockup grids populated');

	-- Create a table to store the selected mockup grids
	CALL raise_notice('Selecting random mockup grids');
	DROP TABLE IF EXISTS mockup_selected_grids;
	CREATE TABLE mockup_selected_grids AS
	(SELECT tpi.proj_id, srmg.taskid, srmg.geom, 5.0 AS percentage_covered
	FROM temp_project_ids tpi
	CROSS JOIN LATERAL select_random_mockup_grids(5.0, tpi.proj_id) srmg)
	UNION ALL
	(SELECT tpi.proj_id, srmg.taskid, srmg.geom, 10.0 AS percentage_covered
	FROM temp_project_ids tpi
	CROSS JOIN LATERAL select_random_mockup_grids(10.0, tpi.proj_id) srmg)
	UNION ALL
	(SELECT tpi.proj_id, srmg.taskid, srmg.geom, 15.0 AS percentage_covered
	FROM temp_project_ids tpi
	CROSS JOIN LATERAL select_random_mockup_grids(15.0, tpi.proj_id) srmg);
	CALL raise_notice('Random mockup grids selected');

	DROP TABLE IF EXISTS mockup_grids;

	-- Calculate nonconnecting nodes for continuation indicator
	DROP TABLE IF EXISTS nonconnecting_nodes;
	CREATE TEMP TABLE nonconnecting_nodes AS
	SELECT tpi.proj_id, gncsen.node AS geom, gncsen.point_type
	FROM temp_project_ids tpi
	CROSS JOIN LATERAL get_nonconnecting_start_end_nodes_in_utm(tpi.proj_id) gncsen
	WHERE tpi.typename = 'ROADS';

	-- Calculate continuation indicator



	-- Calculate duplication indicator
	

	-- DROP TABLE IF EXISTS mockup_selected_grids;
	DROP TABLE IF EXISTS nonconnecting_nodes;

	-- Update the selected projects to indicate that they have been processed
	-- UPDATE selected_projects
	-- SET indicator_cont_dup = indicator_cont_dup + 1;
	-- WHERE proj_id IN (SELECT proj_id FROM temp_project_ids);

	DROP TABLE IF EXISTS temp_project_ids;
	CALL raise_notice('Done');
END $$;