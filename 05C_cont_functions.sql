-- Returns all nodes in the roads of a project
DROP FUNCTION IF EXISTS get_all_node_occurrences_in_roads;
CREATE FUNCTION get_all_node_occurrences_in_roads(project_id INT)
RETURNS TABLE(node geometry, occurrence_count BIGINT) AS $$
BEGIN
    RETURN QUERY
    WITH all_nodes AS (
   	 -- Extract all nodes from each LINESTRING
   	 SELECT (ST_DumpPoints(geom)).geom AS node
   	 FROM get_roads(project_id)
    )
    -- Count occurrences of each node
    SELECT an.node, COUNT(*) AS occurrence_count
    FROM all_nodes AS an
    GROUP BY an.node;
END;
$$ LANGUAGE plpgsql;

-- Returns all start and end nodes in the roads of a project
DROP FUNCTION IF EXISTS get_all_start_end_nodes;
CREATE FUNCTION get_all_start_end_nodes(project_id INT)
RETURNS TABLE(node geometry, point_type TEXT) AS $$
BEGIN
	RETURN QUERY
	SELECT ST_StartPoint(geom) AS node, 'start' AS point_type
	FROM get_roads(project_id)
	UNION ALL
	SELECT ST_EndPoint(geom) AS node, 'end' AS point_type
	FROM get_roads(project_id);
END;
$$ LANGUAGE plpgsql;

-- Returns all nodes in the roads of a project that are not connecting
DROP FUNCTION IF EXISTS get_nonconnecting_start_end_nodes;
CREATE FUNCTION get_nonconnecting_start_end_nodes(project_id INT)
RETURNS TABLE(node geometry, point_type TEXT) AS $$
BEGIN
	RETURN QUERY
	WITH all_node_occurrences AS (
    	-- Get all node occurrences
    	SELECT ganoir.node, ganoir.occurrence_count
    	FROM get_all_node_occurrences_in_roads(project_id) AS ganoir
	),
	start_end_nodes AS (
    	-- Get all start and end nodes
    	SELECT gasen.node, gasen.point_type
    	FROM get_all_start_end_nodes(project_id) as gasen
	)
	-- Select nodes where occurrence count is 1
	SELECT sen.node, sen.point_type
	FROM start_end_nodes AS sen
	JOIN all_node_occurrences AS ano ON sen.node = ano.node
	WHERE ano.occurrence_count = 1;
END;
$$ LANGUAGE plpgsql;

-- Returns all nodes in the roads of a project that are not connecting, in UTM
DROP FUNCTION IF EXISTS get_nonconnecting_start_end_nodes_in_utm;
CREATE FUNCTION get_nonconnecting_start_end_nodes_in_utm(project_id INT)
RETURNS TABLE(node geometry, point_type TEXT) AS $$
DECLARE
	utm_epsg INTEGER;
BEGIN
	-- Determine the SRID of the original grids in UTM
	SELECT get_utm_zone(project_id) INTO utm_epsg;

	RETURN QUERY
	SELECT ST_Transform(gncsen.node, utm_epsg) AS node, gncsen.point_type
	FROM get_nonconnecting_start_end_nodes(project_id) AS gncsen;
END;
$$ LANGUAGE plpgsql;

-- Calculates the continuation metrics for a project:
-- - Number of nodes within shrunk grids
-- - Number of nodes within border buffer
-- - Area of shrunk grids
-- - Area of border buffer
-- - Nodes per unit area in shrunk grids
-- - Nodes per unit area in border buffer
DROP FUNCTION IF EXISTS continuation_per_project;
CREATE FUNCTION continuation_per_project(
	project_id INT,
	shrink_distances DOUBLE PRECISION[],
	grid_type TEXT DEFAULT 'ORIGINAL',
	is_percentage BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
	shrink_distance DOUBLE PRECISION,
	nodes_in_shrunk_grids INTEGER,
	nodes_in_border_buffer INTEGER,
	area_of_shrunk_grids DOUBLE PRECISION,
	area_of_border_buffer DOUBLE PRECISION,
	nodes_per_area_shrunk_grids DOUBLE PRECISION,
	nodes_per_area_border_buffer DOUBLE PRECISION
) AS $$
DECLARE
	distance DOUBLE PRECISION;
	do_mockup_grid BOOLEAN;
	nodes_in_shrunk_grids INTEGER;
	nodes_in_border_buffer INTEGER;
	area_of_shrunk_grids DOUBLE PRECISION;
	area_of_border_buffer DOUBLE PRECISION;
	nodes_per_area_shrunk_grids DOUBLE PRECISION;
	nodes_per_area_border_buffer DOUBLE PRECISION;
	total_number_of_nonconnecting_nodes BIGINT;
	total_area_of_grids DOUBLE PRECISION;
	utm_epsg INTEGER;
	num_distances INT;
BEGIN

	RAISE NOTICE 'TIME % | Project ID: % | Grid type: %', clock_timestamp(), project_id, grid_type;

	IF grid_type = 'MOCKUP' THEN
		do_mockup_grid := TRUE;
	ELSE
		do_mockup_grid := FALSE;
	END IF;

	-- Determine the SRID of the original grids in UTM
	--SELECT get_utm_zone(project_id) INTO utm_epsg;

	-- Save total number of nonconnecting nodes
	WITH grids AS (
        	SELECT ggiu.geom
        	FROM get_grids_in_utm(project_id) AS ggiu
	)
	SELECT COUNT(*) INTO total_number_of_nonconnecting_nodes
	FROM nonconnecting_nodes AS nn
	JOIN grids AS g
		ON ST_Within(nn.geom, g.geom)
	WHERE nn.project_id = continuation_per_project.project_id;

	-- Save total area of grids
	SELECT COALESCE(SUM(ST_Area(ggiu.geom)), 0) INTO total_area_of_grids
    	FROM get_grids_in_utm(project_id, do_mockup_grid) AS ggiu;

	-- Determine the number of shrink distances
	SELECT array_length(shrink_distances, 1)
	INTO num_distances;

	-- Iterate over each shrink distance
	FOR i IN 1..num_distances LOOP
    	-- Get the current shrink distance
    	distance := shrink_distances[i];

		RAISE NOTICE ' - Buffer distance: %, is percentage?: %', distance, is_percentage;

		-- Set all other variables to NULL, in case of an error
		nodes_in_shrunk_grids := NULL;
		nodes_in_border_buffer := NULL;
		area_of_shrunk_grids := NULL;
		area_of_border_buffer := NULL;
		nodes_per_area_shrunk_grids := NULL;
		nodes_per_area_border_buffer := NULL;

    	-- Calculate number of nodes within the shrunk grids
    	WITH shrunk_grids AS MATERIALIZED (
        	SELECT gsgiu.geom
        	FROM get_shrunk_grids_in_utm(project_id, distance, grid_type, is_percentage) AS gsgiu
    	)
    	SELECT COUNT(*) INTO nodes_in_shrunk_grids
    	FROM nonconnecting_nodes AS nn
    	JOIN shrunk_grids AS sg
        	ON ST_Within(nn.geom, sg.geom)
		WHERE nn.project_id = continuation_per_project.project_id;

		-- Calculate number of nodes within buffer
		nodes_in_border_buffer := total_number_of_nonconnecting_nodes - nodes_in_shrunk_grids;

   	 	-- Calculate total area of the shrunk grids
		WITH shrunk_grids AS MATERIALIZED (
        	SELECT gsgiu.geom
        	FROM get_shrunk_grids_in_utm(project_id, distance, grid_type, is_percentage) AS gsgiu
    	)
    	SELECT COALESCE(SUM(ST_Area(sg.geom)), 0) INTO area_of_shrunk_grids
    	FROM shrunk_grids AS sg;

    	-- Calculate total area of the border buffer
    	area_of_border_buffer := total_area_of_grids - area_of_shrunk_grids;

    	-- Calculate nodes per unit area
    	nodes_per_area_shrunk_grids :=
        	CASE WHEN area_of_shrunk_grids > 0 THEN
            	nodes_in_shrunk_grids / area_of_shrunk_grids
        	ELSE
            	0
        	END;

    	nodes_per_area_border_buffer :=
        	CASE WHEN area_of_border_buffer > 0 THEN
            	nodes_in_border_buffer / area_of_border_buffer
        	ELSE
            	0
        	END;

    	-- Return results for the current shrink distance
    	RETURN QUERY
    	SELECT distance,
           	nodes_in_shrunk_grids,
           	nodes_in_border_buffer,
           	area_of_shrunk_grids,
           	area_of_border_buffer,
           	nodes_per_area_shrunk_grids,
           	nodes_per_area_border_buffer;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Calculates the continuation metrics for a set of projects
DROP FUNCTION IF EXISTS continuation;
CREATE FUNCTION continuation(
	project_ids INT[],
	shrink_distances DOUBLE PRECISION[],
	grid_types TEXT[] DEFAULT ARRAY['ORIGINAL']::TEXT[],
	shrink_types TEXT[] DEFAULT ARRAY['distance']::TEXT[]
)
RETURNS TABLE(
	project_id INT,
	grid_type TEXT,
	shrink_distance DOUBLE PRECISION,
	shrink_type TEXT,
	nodes_in_shrunk_grids BIGINT,
	nodes_in_border_buffer BIGINT,
	area_of_shrunk_grids DOUBLE PRECISION,
	area_of_border_buffer DOUBLE PRECISION,
	nodes_per_area_shrunk_grids DOUBLE PRECISION,
	nodes_per_area_border_buffer DOUBLE PRECISION
) AS $$
DECLARE
	current_project_id INT;
	current_grid_type TEXT;
	current_distance DOUBLE PRECISION;
	rec RECORD;
	i INT;
	j INT;
	k INT;
	l INT;
	is_percentage BOOLEAN;
BEGIN
	IF array_length(project_ids, 1) = 0 THEN
		RAISE NOTICE 'No projects to process';
		RETURN;
	END IF;

	-- Iterate over each project_id
	FOR i IN 1..array_length(project_ids, 1) LOOP
    	current_project_id := project_ids[i];

    	-- Iterate over each shrink_distance
    	FOR j IN 1..array_length(shrink_distances, 1) LOOP
        	current_distance := shrink_distances[j];

			-- Iterate over grid_types
			FOR k IN 1..array_length(grid_types, 1) LOOP
				RAISE NOTICE 'Grid type: %', grid_types[k];
				current_grid_type := grid_types[k];

				-- Iterate over shrink_types
				FOR l IN 1..array_length(shrink_types, 1) LOOP
					RAISE NOTICE 'Grid type: %', shrink_types[l];
					is_percentage := shrink_types[l] = 'percentage';
			
					-- Collect results from continuation_per_project
					FOR project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer IN
						SELECT current_project_id AS project_id, grid_types[k] AS grid_type, cpp.shrink_distance, shrink_types[l] AS shrink_type, cpp.nodes_in_shrunk_grids, cpp.nodes_in_border_buffer, cpp.area_of_shrunk_grids, cpp.area_of_border_buffer, cpp.nodes_per_area_shrunk_grids, cpp.nodes_per_area_border_buffer FROM continuation_per_project(current_project_id, ARRAY[current_distance], current_grid_type, is_percentage) as cpp
					LOOP
						-- Return each row
						RETURN NEXT;
					END LOOP;
				END LOOP;
			END LOOP;
		END LOOP;
	END LOOP;

	RETURN;  -- End of function
END;
$$ LANGUAGE plpgsql;
