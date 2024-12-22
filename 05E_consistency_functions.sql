-- DROP FUNCTION IF EXISTS calculate_avg_vertices_per_building_from_task;
-- CREATE FUNCTION calculate_avg_vertices_per_building_from_task(project_id INT, task_id INT)
-- RETURNS TABLE(
--     avg_vertices FLOAT,
--     buildings_count INT
-- ) AS $$
-- DECLARE
--     vertices_sum FLOAT;
-- BEGIN
--     SELECT SUM(ST_NPoints(geom)) INTO vertices_sum
--     FROM get_buildings_from_task(project_id, task_id);

--     SELECT COUNT(*) INTO buildings_count
--     FROM get_buildings_from_task(project_id, task_id);

--     avg_vertices := vertices_sum / NULLIF(buildings_count, 0);

--     RETURN QUERY SELECT avg_vertices, buildings_count;
-- END $$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS calculate_avg_vertices_per_building_from_tasks;
CREATE FUNCTION calculate_avg_vertices_per_building_from_tasks(project_id INT, task_ids INT[])
RETURNS TABLE(
    avg_vertices FLOAT,
    buildings_count INT
) AS $$
DECLARE
    vertices_sum FLOAT;
BEGIN
    SELECT SUM(ST_NPoints(geom)) INTO vertices_sum, COUNT(*) INTO buildings_count
    FROM get_buildings_from_tasks(project_id, task_ids);

    SELECT COUNT(*) INTO buildings_count
    FROM get_buildings_from_tasks(project_id, task_ids);

    avg_vertices := vertices_sum / NULLIF(buildings_count, 0);

    RETURN QUERY SELECT avg_vertices, buildings_count;
END $$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS calculate_gearys_c_for_project;
CREATE FUNCTION calculate_gearys_c_for_project(project_id INT)
RETURNS TABLE(
    task_id INT,
    gearys_c FLOAT
) AS $$
DECLARE
    task RECORD;
    adjacent_task RECORD;
    numerator_sum FLOAT := 0;
    denominator_sum FLOAT := 0;
    mean_vertices FLOAT;
    n INT;
BEGIN
    -- Calculate the mean of avg_vertices for the project
    SELECT AVG(avg_vertices) INTO mean_vertices
    FROM avg_vertices_per_building_per_task
    WHERE project_id = calculate_gearys_c_for_project.project_id;

    -- Calculate the number of tasks in the project
    SELECT COUNT(*) INTO n
    FROM avg_vertices_per_building_per_task
    WHERE project_id = calculate_gearys_c_for_project.project_id;

    FOR task IN
        SELECT taskid, avg_vertices
        FROM avg_vertices_per_building_per_task
        WHERE project_id = calculate_gearys_c_for_project.project_id
    LOOP
        numerator_sum := 0;
        denominator_sum := 0;

        FOR adjacent_task IN
            SELECT adjacent_task_id, avg_vertices
            FROM get_adjacent_tasks(calculate_gearys_c_for_project.project_id, task.taskid) adj
            JOIN avg_vertices_per_building_per_task av
            ON adj.adjacent_task_id = av.taskid
        LOOP
            numerator_sum := numerator_sum + (COALESCE(task.avg_vertices, 0) - COALESCE(adjacent_task.avg_vertices, 0))^2;
            denominator_sum := denominator_sum + (COALESCE(task.avg_vertices, 0) - mean_vertices)^2 + (COALESCE(adjacent_task.avg_vertices, 0) - mean_vertices)^2;
        END LOOP;

        IF denominator_sum != 0 THEN
            RETURN QUERY SELECT task.taskid, (numerator_sum / denominator_sum) * (n / 2);
        ELSE
            RETURN QUERY SELECT task.taskid, NULL::FLOAT;
        END IF;
    END LOOP;
END $$ LANGUAGE plpgsql; 

-- Returns simplified buildings part of a task
-- DROP FUNCTION IF EXISTS get_simplified_buildings_from_task;
-- CREATE FUNCTION get_simplified_buildings_from_task(project_id INT, task_id INT, tolerance FLOAT)
-- RETURNS TABLE(osm_id INTEGER, geom GEOMETRY) AS $$
-- DECLARE
--     utm_epsg INTEGER;
-- BEGIN
--     -- Determine the SRID of the original grids in UTM
--     SELECT ST_SRID((SELECT ggiu.geom
--                     FROM get_grids_in_utm(project_id) ggiu
--                     LIMIT 1))
--     INTO utm_epsg;

-- 	RETURN QUERY
-- 	SELECT b.osm_id, ST_SimplifyPreserveTopology(ST_Transform(b.geom, utm_epsg), tolerance) AS geom
-- 	FROM osm_buildings b
-- 	WHERE b.project_id = get_simplified_buildings_from_task.project_id
--     AND ST_Intersects(b.geom, (
--         SELECT hg.geom
--         FROM get_grids(get_simplified_buildings_from_task.project_id) hg
--         WHERE hg.taskid = task_id
--         ));
-- END;
-- $$ LANGUAGE plpgsql;

-- Returns simplified buildings part of one or more tasks
-- DROP FUNCTION IF EXISTS get_simplified_buildings_from_tasks;
-- CREATE FUNCTION get_simplified_buildings_from_tasks(project_id INT, task_ids INT[], tolerance FLOAT)
-- RETURNS TABLE(osm_id INTEGER, geom GEOMETRY) AS $$
-- DECLARE
--     utm_epsg INTEGER;
-- BEGIN
--     -- Determine the SRID of the original grids in UTM
--     SELECT ST_SRID((SELECT ggiu.geom
--                     FROM get_grids_in_utm(project_id) ggiu
--                     LIMIT 1))
--     INTO utm_epsg;

-- 	RETURN QUERY
-- 	SELECT b.osm_id, ST_SimplifyPreserveTopology(ST_Transform(b.geom, utm_epsg), tolerance) AS geom
-- 	FROM osm_buildings b
-- 	WHERE b.project_id = get_simplified_buildings_from_tasks.project_id
--     AND ST_Intersects(b.geom, (
--         SELECT ST_Union(hg.geom) AS geom
--         FROM get_grids(get_simplified_buildings_from_tasks.project_id) hg
--         WHERE hg.taskid = ANY(task_ids)
--         ));
-- END;
-- $$ LANGUAGE plpgsql;

-- Get ratio from simplified buildings to original buildings
-- DROP FUNCTION IF EXISTS get_ratio_simplified_buildings;
-- CREATE FUNCTION get_ratio_simplified_buildings(project_id INT, task_id INT, tolerance FLOAT DEFAULT 5.0)
-- RETURNS TABLE(
--     average_vertices_original FLOAT,
--     average_vertices_simplified FLOAT,
--     average_simplified_area_covered_from_original FLOAT,
--     number_of_buildings INT,
--     task_area FLOAT,
--     tolerance_used FLOAT
-- ) AS $$
-- DECLARE
--     original_area FLOAT;
--     simplified_area FLOAT;
--     original_vertices FLOAT;
--     simplified_vertices FLOAT;
--     simplified_area_covered FLOAT;
--     original_vertices_sum FLOAT;
--     simplified_vertices_sum FLOAT;
--     simplified_area_covered_sum FLOAT;
--     number_of_buildings_sum INT;
--     task_area_sum FLOAT;
-- BEGIN
--     WITH task AS (
--         SELECT ggiu.geom AS geom
--         FROM get_grids_in_utm(project_id) ggiu
--         WHERE ggiu.taskid = get_ratio_simplified_buildings.task_id
--     ),
--     original_buildings AS (
--         SELECT gbft.osm_id, gbft.geom AS geom
--         FROM get_buildings_from_task(project_id, task_id) gbft
--     ),
--     simplified_buildings AS (
--         SELECT gsft.osm_id, gsft.geom AS geom
--         FROM get_simplified_buildings_from_tasks(project_id, ARRAY[task_id], tolerance) gsft
--     )
--     SELECT
--         AVG(ST_NPoints(ob.geom)) AS avg_vertices_original,
--         AVG(ST_NPoints(sb.geom)) AS avg_vertices_simplified,
--         AVG(ST_Area(ST_Intersection(ob.geom, sb.geom))) / NULLIF(AVG(ST_Area(ob.geom)), 0) AS avg_simplified_area_covered_from_original,
--         COUNT(ob.osm_id) AS num_buildings,
--         ST_Area((SELECT ST_Union(t.geom) FROM task t)) AS task_area,
--         tolerance AS tolerance_used
--     INTO
--         average_vertices_original,
--         average_vertices_simplified,
--         average_simplified_area_covered_from_original,
--         number_of_buildings,
--         task_area,
--         tolerance_used
--     FROM original_buildings ob
--     JOIN simplified_buildings sb ON ob.osm_id = sb.osm_id;

--     RETURN QUERY
--     SELECT
--         average_vertices_original,
--         average_vertices_simplified,
--         average_simplified_area_covered_from_original,
--         number_of_buildings,
--         task_area,
--         tolerance_used;
-- END;
-- $$ LANGUAGE plpgsql;

-- Get ratio from simplified buildings to original buildings
-- DROP FUNCTION IF EXISTS get_ratio_simplified_buildings_tasks;
-- CREATE FUNCTION get_ratio_simplified_buildings_tasks(project_id INT, task_ids INT[], tolerance FLOAT DEFAULT 5.0)
-- RETURNS TABLE(
--     average_vertices_original FLOAT,
--     average_vertices_simplified FLOAT,
--     average_simplified_area_covered_from_original FLOAT,
--     number_of_buildings INT,
--     task_area FLOAT,
--     tolerance_used FLOAT
-- ) AS $$
-- DECLARE
--     original_area FLOAT;
--     simplified_area FLOAT;
--     original_vertices FLOAT;
--     simplified_vertices FLOAT;
--     simplified_area_covered FLOAT;
--     original_vertices_sum FLOAT;
--     simplified_vertices_sum FLOAT;
--     simplified_area_covered_sum FLOAT;
--     number_of_buildings_sum INT;
--     task_area_sum FLOAT;
-- BEGIN
--     WITH tasks AS (
--         SELECT ggiu.geom AS geom
--         FROM get_grids_in_utm(project_id) ggiu
--         WHERE ggiu.taskid = ANY(get_ratio_simplified_buildings_tasks.task_ids)
--     ),
--     original_buildings AS (
--         SELECT gbft.osm_id, gbft.geom AS geom
--         FROM get_buildings_from_tasks(project_id, task_ids) gbft
--     ),
--     simplified_buildings AS (
--         SELECT gsft.osm_id, gsft.geom AS geom
--         FROM get_simplified_buildings_from_tasks(project_id, task_ids, tolerance) gsft
--     )
--     SELECT
--         AVG(ST_NPoints(ob.geom)) AS avg_vertices_original,
--         AVG(ST_NPoints(sb.geom)) AS avg_vertices_simplified,
--         AVG(ST_Area(ST_Intersection(ob.geom, sb.geom))) / NULLIF(AVG(ST_Area(ob.geom)), 0) AS avg_simplified_area_covered_from_original,
--         COUNT(ob.osm_id) AS num_buildings,
--         ST_Area((SELECT ST_Union(t.geom) FROM tasks t)) AS task_area,
--         tolerance AS tolerance_used
--     INTO
--         average_vertices_original,
--         average_vertices_simplified,
--         average_simplified_area_covered_from_original,
--         number_of_buildings,
--         task_area,
--         tolerance_used
--     FROM original_buildings ob
--     JOIN simplified_buildings sb ON ob.osm_id = sb.osm_id;

--     RETURN QUERY
--     SELECT
--         average_vertices_original,
--         average_vertices_simplified,
--         average_simplified_area_covered_from_original,
--         number_of_buildings,
--         task_area,
--         tolerance_used;
-- END;
-- $$ LANGUAGE plpgsql;

-- -- Get ratio for several projects and task ids
-- DROP FUNCTION IF EXISTS get_ratio_simplified_buildings_multiple;
-- CREATE FUNCTION get_ratio_simplified_buildings_multiple(project_ids INT[], tolerance FLOAT DEFAULT 5.0)
-- RETURNS TABLE(
--     project_id INT,
--     task_id INT,
--     average_vertices_original FLOAT,
--     average_vertices_simplified FLOAT,
--     average_simplified_area_covered_from_original FLOAT,
--     number_of_buildings INT,
--     task_area FLOAT,
--     tolerance_used FLOAT
-- ) AS $$
-- DECLARE
--     current_project_id INT;
--     current_task_id INT;
--     task_ids_cursor REFCURSOR;
--     task_id_record RECORD;
-- BEGIN
--     FOR current_project_id IN SELECT unnest(project_ids) LOOP
--         RAISE NOTICE 'TIME % | Starting project: %', clock_timestamp(), current_project_id;

--         -- Open a cursor to fetch task ids for the current project
--         OPEN task_ids_cursor FOR
--         SELECT taskid AS ids
--         FROM get_grids(current_project_id);
        
--         -- Loop through each task id fetched by the cursor
--         LOOP
--             FETCH task_ids_cursor INTO task_id_record;
--             EXIT WHEN NOT FOUND;
--             current_task_id := task_id_record.ids;
            
--             RETURN QUERY
--             SELECT
--                 current_project_id,
--                 current_task_id,
--                 grsb.average_vertices_original,
--                 grsb.average_vertices_simplified,
--                 grsb.average_simplified_area_covered_from_original,
--                 grsb.number_of_buildings,
--                 grsb.task_area,
--                 grsb.tolerance_used
--             FROM get_ratio_simplified_buildings(current_project_id, ARRAY[current_task_id], tolerance) grsb;
--         END LOOP;
        
--         -- Close the cursor
--         CLOSE task_ids_cursor;
--     END LOOP;
-- END;
-- $$ LANGUAGE plpgsql;

-- -- Get ratio for several projects and task ids
-- DROP FUNCTION IF EXISTS get_ratio_simplified_buildings_multiple_adjacent;
-- CREATE FUNCTION get_ratio_simplified_buildings_multiple_adjacent(project_ids INT[], tolerance FLOAT DEFAULT 5.0)
-- RETURNS TABLE(
--     project_id INT,
--     task_id INT,
--     average_vertices_original FLOAT,
--     average_vertices_simplified FLOAT,
--     average_simplified_area_covered_from_original FLOAT,
--     number_of_buildings INT,
--     number_of_tasks INT,
--     task_area FLOAT,
--     tolerance_used FLOAT
-- ) AS $$
-- DECLARE
--     current_project_id INT;
--     current_task_id INT;
--     task_ids_cursor REFCURSOR;
--     task_id_record RECORD;
--     adjacent_tasks INT[];
-- BEGIN
--     FOR current_project_id IN SELECT unnest(project_ids) LOOP
--         RAISE NOTICE 'TIME % | Starting project: %', clock_timestamp(), current_project_id;

--         -- Open a cursor to fetch task ids for the current project
--         OPEN task_ids_cursor FOR
--         SELECT taskid AS ids
--         FROM get_grids(current_project_id);

--         SELECT array_agg(gat.taskid) INTO adjacent_tasks
--         FROM get_adjacent_tasks(current_project_id, current_task_id) gat;
        
--         -- Loop through each task id fetched by the cursor
--         LOOP
--             FETCH task_ids_cursor INTO task_id_record;
--             EXIT WHEN NOT FOUND;
--             current_task_id := task_id_record.ids;

--             RETURN QUERY
--             SELECT
--                 current_project_id,
--                 current_task_id,
--                 grsb.average_vertices_original,
--                 grsb.average_vertices_simplified,
--                 grsb.average_simplified_area_covered_from_original,
--                 grsb.number_of_buildings,
--                 array_length(adjacent_tasks, 1) AS number_of_tasks,
--                 grsb.task_area,
--                 grsb.tolerance_used
--             FROM get_ratio_simplified_buildings_tasks(current_project_id, adjacent_tasks, tolerance) grsb;
--         END LOOP;
        
--         -- Close the cursor
--         CLOSE task_ids_cursor;
--     END LOOP;
-- END;
-- $$ LANGUAGE plpgsql;
