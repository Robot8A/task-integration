-- Returns grids part of a project
CREATE OR REPLACE FUNCTION get_grids(project_id INT)
RETURNS TABLE(gid INTEGER, taskid INTEGER, geom GEOMETRY) AS $$
BEGIN
	RETURN QUERY
	SELECT g.gid, g.taskid, g.geom
	FROM hotosm_grids g
	WHERE g.project_id = get_grids.project_id;
END;
$$ LANGUAGE plpgsql;

-- Returns true if all grids are fully adjacent
CREATE OR REPLACE FUNCTION project_has_fully_adjacent_cells(project_id INT)
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
CREATE OR REPLACE FUNCTION get_buildings(project_id INT)
RETURNS TABLE(osm_id INTEGER, geom GEOMETRY) AS $$
BEGIN
	RETURN QUERY
	SELECT b.osm_id, ST_Intersection(b.geom, g.geom) AS geom
	FROM osm_buildings b
	JOIN get_grids(get_buildings.project_id) g
	ON ST_Intersects(b.geom, g.geom);
END;
$$ LANGUAGE plpgsql;

-- Returns roads part of a project
CREATE OR REPLACE FUNCTION get_roads(project_id INT)
RETURNS TABLE(osm_id INTEGER, geom GEOMETRY) AS $$
BEGIN
	RETURN QUERY
	SELECT r.osm_id, ST_Intersection(r.geom, g.geom) AS geom
	FROM osm_roads r
	JOIN get_grids(get_roads.project_id) g
	ON ST_Intersects(r.geom, g.geom);
END;
$$ LANGUAGE plpgsql;

-- Returns an accurate UTM zone number for a given geometry
CREATE OR REPLACE FUNCTION calculate_utm_zone(geometry GEOMETRY)
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
CREATE OR REPLACE FUNCTION get_grids_in_utm(project_id INT)
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
	FROM get_grids(project_id) AS gg;
END;
$$ LANGUAGE plpgsql;

-- Shrinks a geometry by a given distance
CREATE OR REPLACE FUNCTION shrink_geometry(geom geometry, shrink_distance double precision)
RETURNS geometry AS $$
BEGIN
	-- Apply the negative buffer to shrink the geometry
	RETURN ST_Buffer(geom, -shrink_distance);
END;
$$ LANGUAGE plpgsql;

-- Returns shrunk grids in UTM projection
CREATE OR REPLACE FUNCTION get_shrunk_grids_in_utm(project_id INT, shrink_distance DOUBLE PRECISION)
RETURNS TABLE(gid INTEGER, taskid INTEGER, geom GEOMETRY) AS $$
BEGIN
	RETURN QUERY
	WITH utm_grids AS (
    	SELECT ggiu.gid, ggiu.taskid, ggiu.geom
    	FROM get_grids_in_utm(project_id) AS ggiu
	)
	SELECT utm_grids.gid, utm_grids.taskid, shrink_geometry(utm_grids.geom, shrink_distance) AS geom
	FROM utm_grids;
END;
$$ LANGUAGE plpgsql;