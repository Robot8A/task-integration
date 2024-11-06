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
    utm_epsg INT;
BEGIN
    -- Determine the SRID of the original grids in UTM
	SELECT get_utm_zone(project_id) INTO utm_epsg;

    RETURN QUERY
    WITH buildings AS (
        SELECT bu.osm_id, bu.geom AS geom
        FROM buildings_utm bu
        WHERE bu.project_id = project_id
    ),
    filtered_buildings AS (
        SELECT a.osm_id AS building_a_id, a.geom AS building_a_geom, b.osm_id AS building_b_id, b.geom AS building_b_geom, ST_Intersection(a.geom, b.geom) AS intersection_geom
        FROM buildings a
        JOIN buildings b ON a.geom && b.geom  -- Use bounding box intersection, to reduce complexity
        WHERE a.osm_id < b.osm_id
        AND ST_Intersects(a.geom, b.geom)
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
