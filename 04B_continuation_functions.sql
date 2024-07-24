-- Returns all nodes in the roads of a project
CREATE OR REPLACE FUNCTION get_all_node_occurrences_in_roads(project_id INT)
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
CREATE OR REPLACE FUNCTION get_all_start_end_nodes(project_id INT)
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
CREATE OR REPLACE FUNCTION get_nonconnecting_start_end_nodes(project_id INT)
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

-- Calculates the continuation metrics for a project:
-- - Number of nodes within shrunk grids
-- - Number of nodes within border buffer
-- - Area of shrunk grids
-- - Area of border buffer
-- - Nodes per unit area in shrunk grids
-- - Nodes per unit area in border buffer
CREATE OR REPLACE FUNCTION continuation_per_project(
	project_id INT,
	shrink_distances DOUBLE PRECISION[]
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
	nodes_in_shrunk_grids INTEGER;
	nodes_in_border_buffer INTEGER;
	area_of_shrunk_grids DOUBLE PRECISION;
	area_of_border_buffer DOUBLE PRECISION;
	nodes_per_area_shrunk_grids DOUBLE PRECISION;
	nodes_per_area_border_buffer DOUBLE PRECISION;
	utm_epsg INTEGER;
	num_distances INT;
BEGIN
	-- Determine the SRID of the original grids in UTM
	SELECT ST_SRID((SELECT geom
                	FROM get_grids_in_utm(project_id)
                	LIMIT 1))
	INTO utm_epsg;

	-- Determine the number of shrink distances
	SELECT array_length(shrink_distances, 1)
	INTO num_distances;

	-- Iterate over each shrink distance
	FOR i IN 1..num_distances LOOP
    	-- Get the current shrink distance
    	distance := shrink_distances[i];

    	-- Calculate number of nodes within the shrunk grids
    	WITH shrunk_grids AS (
        	SELECT gsgiu.gid, gsgiu.geom
        	FROM get_shrunk_grids_in_utm(project_id, distance) AS gsgiu
    	),
    	nonconnecting_nodes AS (
        	SELECT ST_Transform(gncsen.node, utm_epsg) AS node
        	FROM get_nonconnecting_start_end_nodes(project_id) AS gncsen
    	)
    	SELECT COUNT(*) INTO nodes_in_shrunk_grids
    	FROM nonconnecting_nodes AS nn
    	JOIN shrunk_grids AS sg
        	ON ST_Within(nn.node, sg.geom);

   	 WITH shrunk_grids AS (
        	SELECT gsgiu.gid, gsgiu.geom
        	FROM get_shrunk_grids_in_utm(project_id, distance) AS gsgiu
    	)
    	-- Calculate total area of the shrunk grids
    	SELECT COALESCE(SUM(ST_Area(sg.geom)), 0) INTO area_of_shrunk_grids
    	FROM shrunk_grids AS sg;

    	-- Calculate number of nodes within the border buffer
    	WITH original_grids AS (
        	SELECT ggiu.gid, ggiu.geom
        	FROM get_grids_in_utm(project_id) AS ggiu
    	),
    	shrunk_grids AS (
        	SELECT gsgiu.gid, gsgiu.geom
        	FROM get_shrunk_grids_in_utm(project_id, distance) AS gsgiu
    	),
    	border_buffer AS (
        	SELECT og.gid, ST_Difference(og.geom, sg.geom) AS geom
        	FROM original_grids AS og
        	JOIN shrunk_grids AS sg
            	ON og.gid = sg.gid
    	),
    	nonconnecting_nodes AS (
        	SELECT ST_Transform(gncsen.node, utm_epsg) AS node
        	FROM get_nonconnecting_start_end_nodes(project_id) AS gncsen
    	)
    	SELECT COUNT(*) INTO nodes_in_border_buffer
    	FROM nonconnecting_nodes AS nn
    	JOIN border_buffer AS bb
        	ON ST_Within(nn.node, bb.geom);

   	 WITH original_grids AS (
        	SELECT ggiu.gid, ggiu.geom
        	FROM get_grids_in_utm(project_id) AS ggiu
    	),
   	 shrunk_grids AS (
        	SELECT gsgiu.gid, gsgiu.geom
        	FROM get_shrunk_grids_in_utm(project_id, distance) AS gsgiu
    	),
   	 border_buffer AS (
        	SELECT og.gid, ST_Difference(og.geom, sg.geom) AS geom
        	FROM original_grids AS og
        	JOIN shrunk_grids AS sg
            	ON og.gid = sg.gid
    	)
    	-- Calculate total area of the border buffer
    	SELECT COALESCE(SUM(ST_Area(bb.geom)), 0) INTO area_of_border_buffer
    	FROM border_buffer AS bb;

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
CREATE OR REPLACE FUNCTION continuation(
	project_ids INT[],
	shrink_distances DOUBLE PRECISION[]
)
RETURNS TABLE(
	project_id INT,
	shrink_distance DOUBLE PRECISION,
	nodes_in_shrunk_grids BIGINT,
	nodes_in_border_buffer BIGINT,
	area_of_shrunk_grids DOUBLE PRECISION,
	area_of_border_buffer DOUBLE PRECISION,
	nodes_per_area_shrunk_grids DOUBLE PRECISION,
	nodes_per_area_border_buffer DOUBLE PRECISION
) AS $$
DECLARE
	current_project_id INT;
	current_distance DOUBLE PRECISION;
	rec RECORD;
	i INT;
BEGIN
	-- Iterate over each project_id
	FOR i IN 1..array_length(project_ids, 1) LOOP
    	current_project_id := project_ids[i];

    	-- Iterate over each shrink_distance
    	FOR j IN 1..array_length(shrink_distances, 1) LOOP
        	current_distance := shrink_distances[j];

        	-- Collect results from continuation_per_project
        	FOR project_id, shrink_distance, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer IN
            	SELECT current_project_id AS project_id, cpp.shrink_distance, cpp.nodes_in_shrunk_grids, cpp.nodes_in_border_buffer, cpp.area_of_shrunk_grids, cpp.area_of_border_buffer, cpp.nodes_per_area_shrunk_grids, cpp.nodes_per_area_border_buffer FROM continuation_per_project(current_project_id, ARRAY[current_distance]) as cpp
        	LOOP
            	-- Return each row
            	RETURN NEXT;
        	END LOOP;
    	END LOOP;
	END LOOP;

	RETURN;  -- End of function
END;
$$ LANGUAGE plpgsql;
