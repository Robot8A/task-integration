DROP FUNCTION IF EXISTS transform_buildings_to_utm;
CREATE FUNCTION transform_buildings_to_utm(
    project_id INT
)
RETURNS TABLE(osm_id INT, geom GEOMETRY) AS $$
DECLARE
    utm_epsg INT;
BEGIN
    -- Determine the SRID of the original grids in UTM
	SELECT get_utm_zone(project_id) INTO utm_epsg;

    RETURN QUERY
    WITH grids AS (
        SELECT g.geom from get_grids(project_id) AS g
    ),
    buildings_wgs84 AS (
        SELECT b.osm_id, b.geom AS geom
        FROM get_buildings(project_id) b
    )
    
    SELECT bw.osm_id, ST_Transform(bw.geom, utm_epsg) AS geom
    FROM buildings_wgs84 bw;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS get_duplicated_buildings;
CREATE FUNCTION get_duplicated_buildings(
    project_id INT,
    threshold FLOAT DEFAULT 0.2
)
RETURNS TABLE(building_a_id INT, building_b_id INT, intersection_geom GEOMETRY) AS $$
DECLARE
BEGIN
    RETURN QUERY
    WITH filtered_buildings AS (
        SELECT a.osm_id AS building_a_id, a.geom_utm AS building_a_geom, b.osm_id AS building_b_id, b.geom_utm AS building_b_geom, ST_Intersection(a.geom_utm, b.geom_utm) AS intersection_geom
        FROM buildings a
        JOIN buildings b ON a.geom_utm && b.geom_utm  -- Use bounding box intersection, to reduce complexity
		WHERE a.project_id = get_duplicated_buildings.project_id
		AND b.project_id = get_duplicated_buildings.project_id
        AND a.osm_id < b.osm_id
        AND ST_Intersects(a.geom_utm, b.geom_utm)
    )
    SELECT fb.building_a_id, fb.building_b_id, fb.intersection_geom
    FROM filtered_buildings fb
    WHERE ST_GeometryType(fb.intersection_geom) = 'ST_Polygon'
    AND (
        (ST_Area(fb.intersection_geom) / ST_Area(fb.building_a_geom)) >= threshold
        OR
        (ST_Area(fb.intersection_geom) / ST_Area(fb.building_b_geom)) >= threshold
    );
END;
$$ LANGUAGE plpgsql;


-- Calculates the duplication metrics for a project:
-- - Number of nodes within shrunk grids
-- - Number of nodes within border buffer
-- - Area of shrunk grids
-- - Area of border buffer
-- - Nodes per unit area in shrunk grids
-- - Nodes per unit area in border buffer
DROP FUNCTION IF EXISTS duplication_per_project;
CREATE FUNCTION duplication_per_project(
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
	total_number_of_duplicated_buildings BIGINT;
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
	SELECT get_utm_zone(project_id) INTO utm_epsg;

	-- Save total number of duplicated buildings
	WITH grids AS (
        	SELECT ggiu.geom
        	FROM get_grids_in_utm(project_id) AS ggiu
	)
	SELECT COUNT(*) INTO total_number_of_duplicated_buildings
	FROM duplicated_buildings AS db
	JOIN grids AS g
		ON ST_Within(db.intersection_centroid, g.geom)
	WHERE db.project_id = duplication_per_project.project_id;

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
    	WITH shrunk_grids AS (
        	SELECT gsgiu.taskid, gsgiu.geom
        	FROM get_shrunk_grids_in_utm(project_id, distance, grid_type, is_percentage) AS gsgiu
    	)
    	SELECT COUNT(*) INTO nodes_in_shrunk_grids
    	FROM duplicated_buildings AS db
    	JOIN shrunk_grids AS sg
        	ON ST_Within(db.intersection_centroid, sg.geom)
		WHERE db.project_id = duplication_per_project.project_id;

		-- Calculate number of nodes within buffer
		nodes_in_border_buffer := total_number_of_duplicated_buildings - nodes_in_shrunk_grids;

   	 	-- Calculate total area of the shrunk grids
		WITH shrunk_grids AS (
        	SELECT gsgiu.taskid, gsgiu.geom
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

-- Calculates the duplication metrics for a set of projects
DROP FUNCTION IF EXISTS duplication;
CREATE FUNCTION duplication(
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
			
					-- Collect results from duplication_per_project
					FOR project_id, grid_type, shrink_distance, shrink_type, nodes_in_shrunk_grids, nodes_in_border_buffer, area_of_shrunk_grids, area_of_border_buffer, nodes_per_area_shrunk_grids, nodes_per_area_border_buffer IN
						SELECT current_project_id AS project_id, grid_types[k] AS grid_type, cpp.shrink_distance, shrink_types[l] AS shrink_type, cpp.nodes_in_shrunk_grids, cpp.nodes_in_border_buffer, cpp.area_of_shrunk_grids, cpp.area_of_border_buffer, cpp.nodes_per_area_shrunk_grids, cpp.nodes_per_area_border_buffer FROM duplication_per_project(current_project_id, ARRAY[current_distance], current_grid_type, is_percentage) as cpp
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