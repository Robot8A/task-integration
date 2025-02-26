


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