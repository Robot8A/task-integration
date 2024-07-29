-- Generates mockup grids
DROP FUNCTION IF EXISTS generate_grid;
CREATE FUNCTION generate_grid(input_geom geometry, x_width DOUBLE PRECISION, y_height DOUBLE PRECISION)
RETURNS TABLE (id INT, geom geometry(POLYGON, 4326)) AS $$
DECLARE
	minx DOUBLE PRECISION;
	miny DOUBLE PRECISION;
	maxx DOUBLE PRECISION;
	maxy DOUBLE PRECISION;
	x DOUBLE PRECISION;
	y DOUBLE PRECISION;
	grid_id integer := 0;
	grid_cell geometry;
BEGIN
	-- Get the bounding box of the input geometry
	SELECT
    	ST_XMin(input_geom),
    	ST_YMin(input_geom),
    	ST_XMax(input_geom),
    	ST_YMax(input_geom)
	INTO
    	minx,
    	miny,
    	maxx,
    	maxy;

	-- Generate the grid cells and return them
	x := minx;
	WHILE x < maxx LOOP
    	y := miny;
    	WHILE y < maxy LOOP
        	grid_id := grid_id + 1;
        	grid_cell := ST_SetSRID(
                        	ST_MakePolygon(
                            	ST_MakeLine(ARRAY[
                                	ST_Point(x, y),
                                	ST_Point(x + x_width, y),
                                	ST_Point(x + x_width, y + y_height),
                                	ST_Point(x, y + y_height),
                                	ST_Point(x, y)
                            	])
                        	), 4326
                    	);
        	geom := ST_Intersection(grid_cell, input_geom);
        	IF NOT ST_IsEmpty(geom) THEN
            	id := grid_id;
            	RETURN NEXT;
        	END IF;
        	y := y + y_height;
    	END LOOP;
    	x := x + x_width;
	END LOOP;
END $$ LANGUAGE plpgsql;

-- Generates mockup grid with project_id
DROP FUNCTION IF EXISTS generate_mockup_grid;
CREATE FUNCTION generate_mockup_grid(project_id INT)
RETURNS VOID AS $$
RETURNS TABLE (id INT, geom geometry(POLYGON, 4326)) AS $$
BEGIN
RETURN QUERY
		SELECT 0 AS gid, 0 AS taskid, geng.geom
		FROM generate_grid(
			(SELECT ST_Union(gg.geom) FROM get_grids(project_id, FALSE) AS gg),
			0.01,
			0.01
		) AS geng;
END;
$$ LANGUAGE plpgsql;

-- Returns grids part of a project
DROP FUNCTION IF EXISTS get_grids;
CREATE FUNCTION get_grids(project_id INT, do_mockup_grid BOOLEAN DEFAULT FALSE)
RETURNS TABLE(gid INTEGER, taskid INTEGER, geom GEOMETRY) AS $$
BEGIN
	IF do_mockup_grid THEN
		RETURN QUERY
		SELECT 0 AS gid, 0 AS taskid, mg.geom
		FROM mockup_grids AS mg
		WHERE mg.project_id = get_grids.project_id;
	ELSE
		RETURN QUERY
		SELECT g.gid, g.taskid, g.geom
		FROM hotosm_grids g
		WHERE g.project_id = get_grids.project_id;
	END IF;
END;
$$ LANGUAGE plpgsql;

-- Returns true if all grids are fully adjacent
DROP FUNCTION IF EXISTS project_has_fully_adjacent_cells;
CREATE FUNCTION project_has_fully_adjacent_cells(project_id INT)
RETURNS BOOLEAN AS $$
DECLARE
	num_clusters INT;
BEGIN
	-- Count the number of unique clusters where geometries intersect
	SELECT COUNT(DISTINCT cluster) INTO num_clusters
	FROM (
    	SELECT
        	unnest(ST_ClusterIntersecting(geom)) AS cluster
    	FROM
        	get_grids(project_id)
	) AS clustered_areas;

	-- Return true if all geometries are in a single cluster, otherwise false
	RETURN num_clusters = 1;
END;
$$ LANGUAGE plpgsql;

-- Returns buildings part of a project
--DROP FUNCTION IF EXISTS get_buildings;
--CREATE FUNCTION get_buildings(project_id INT)
--RETURNS TABLE(osm_id INTEGER, geom GEOMETRY) AS $$
--BEGIN
--	RETURN QUERY
--	SELECT b.osm_id, b.geom
--	FROM osm_buildings b
--	WHERE b.project_id = get_buildings.project_id;
--END;
--$$ LANGUAGE plpgsql;

-- Returns roads part of a project
DROP FUNCTION IF EXISTS get_roads;
CREATE FUNCTION get_roads(project_id INT)
RETURNS TABLE(osm_id INTEGER, geom GEOMETRY) AS $$
BEGIN
	RETURN QUERY
	SELECT r.osm_id, r.geom
	FROM osm_roads r
	WHERE r.project_id = get_roads.project_id;
END;
$$ LANGUAGE plpgsql;

-- Returns an accurate UTM zone number for a given geometry
DROP FUNCTION IF EXISTS calculate_utm_zone;
CREATE FUNCTION calculate_utm_zone(geometry GEOMETRY)
RETURNS TEXT AS $$
DECLARE
	lat NUMERIC;
	lon NUMERIC;
	zone_number INT;
	epsg_number TEXT;
BEGIN
	-- Calculate the centroid of the bounding box of the geometry
	SELECT ST_Y(ST_Centroid(ST_Extent(geometry))), ST_X(ST_Centroid(ST_Extent(geometry)))
	INTO lat, lon;

	-- Calculate the UTM zone number
	zone_number := FLOOR((lon + 180) / 6) + 1;

	-- Determine the EPSG code based on latitude
	IF lat >= 0 THEN
    	epsg_number := '326' || LPAD(zone_number::TEXT, 2, '0');
	ELSE
    	epsg_number := '327' || LPAD(zone_number::TEXT, 2, '0');
	END IF;

	RETURN epsg_number;
END;
$$ LANGUAGE plpgsql;

-- Returns grids in UTM projection
DROP FUNCTION IF EXISTS get_grids_in_utm;
CREATE FUNCTION get_grids_in_utm(project_id INT, do_mockup_grid BOOLEAN DEFAULT FALSE)
RETURNS TABLE(gid INTEGER, taskid INTEGER, geom GEOMETRY) AS $$
DECLARE
	utm_epsg INTEGER;
BEGIN
	-- Calculate the UTM EPSG code
	SELECT calculate_utm_zone(union_gg.geom)::INTEGER INTO utm_epsg
	FROM (
    	SELECT ST_Union(gg.geom) AS geom
    	FROM get_grids(project_id) AS gg
	) AS union_gg
	LIMIT 1;

	-- Return transformed geometries using the calculated UTM EPSG code
	RETURN QUERY
	SELECT gg.gid, gg.taskid, ST_Transform(gg.geom, utm_epsg) AS geom
	FROM get_grids(project_id, do_mockup_grid) AS gg;
END;
$$ LANGUAGE plpgsql;

-- Shrinks a geometry by a given distance
DROP FUNCTION IF EXISTS shrink_geometry;
CREATE FUNCTION shrink_geometry(geom geometry, shrink_distance double precision)
RETURNS geometry AS $$
BEGIN
	-- Apply the negative buffer to shrink the geometry
	RETURN ST_Buffer(geom, -shrink_distance);
END;
$$ LANGUAGE plpgsql;

-- Returns shrunk grids in UTM projection
DROP FUNCTION IF EXISTS get_shrunk_grids_in_utm;
CREATE FUNCTION get_shrunk_grids_in_utm(project_id INT, shrink_distance DOUBLE PRECISION, do_mockup_grid BOOLEAN DEFAULT FALSE)
RETURNS TABLE(gid INTEGER, taskid INTEGER, geom GEOMETRY) AS $$
BEGIN
	RETURN QUERY
	WITH utm_grids AS (
    	SELECT ggiu.gid, ggiu.taskid, ggiu.geom
    	FROM get_grids_in_utm(project_id, do_mockup_grid) AS ggiu
	)
	SELECT utm_grids.gid, utm_grids.taskid, shrink_geometry(utm_grids.geom, shrink_distance) AS geom
	FROM utm_grids;
END;
$$ LANGUAGE plpgsql;

-- Get buildings part of a task
DROP FUNCTION IF EXISTS get_buildings_from_task;
CREATE FUNCTION get_buildings_from_task(project_id INT, task_id INT)
RETURNS TABLE(osm_id INTEGER, geom GEOMETRY) AS $$
DECLARE
    utm_epsg INTEGER;
BEGIN
     -- Determine the SRID of the original grids in UTM
    SELECT ST_SRID((SELECT ggiu.geom
                    FROM get_grids_in_utm(project_id) ggiu
                    LIMIT 1))
    INTO utm_epsg;

    RETURN QUERY
    SELECT b.osm_id, ST_Transform(b.geom, utm_epsg)
    FROM osm_buildings b
    WHERE b.project_id = get_buildings_from_task.project_id
    AND ST_Intersects(b.geom, (
        SELECT hg.geom
        FROM get_grids(get_buildings_from_task.project_id) hg
        WHERE hg.taskid = task_id
        ));
END;
$$ LANGUAGE plpgsql;

-- Returns task ids of the adjacent tasks
DROP FUNCTION IF EXISTS get_adjacent_tasks;
CREATE FUNCTION get_adjacent_tasks(project_id INT, task_id INT)
RETURNS TABLE(taskid INT) AS $$
BEGIN
	RETURN QUERY
	SELECT g.taskid
	FROM get_grids(project_id) g
	WHERE ST_Touches(
		(SELECT hg.geom
		 FROM get_grids(project_id) hg
		 WHERE hg.taskid = task_id
		),
		g.geom
	);
END;
$$ LANGUAGE plpgsql;
