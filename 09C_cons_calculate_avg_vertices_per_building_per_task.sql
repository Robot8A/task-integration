DO $$
DECLARE
    source TEXT := 'OSM';
    applied_function TEXT := 'MEDIAN';
BEGIN
    RAISE NOTICE '---------------------------------------------------------------';
    RAISE NOTICE '-- 09C_cons_calculate_avg_vertices_per_building_per_task.sql --';
    RAISE NOTICE '---------------------------------------------------------------';

    -- Get the selected projects
	CALL raise_notice('Selecting projects');
    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_project_ids') THEN
        DROP TABLE temp_project_ids;
    END IF;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT proj_id
	FROM selected_projects
    WHERE (source = 'OSM' AND indicator_cons = 8 OR source != 'OSM' AND indicator_cons_ai = 8)
    AND typename = 'BUILDINGS'
	ORDER BY proj_id
	;
	CALL raise_notice('Projects selected');

    -- Calculate the average number of vertices of the buildings in each task
    CALL raise_notice('Calculating ' || applied_function || ' number of vertices per building per task');
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE lower(table_name) = 'avg_vertices_per_building_per_task') THEN
        IF source = 'OSM' THEN
            IF applied_function = 'AVG' THEN
                CREATE TABLE avg_vertices_per_building_per_task AS
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                SELECT p.proj_id, tg.taskid, AVG(ST_NPoints(tb.geom_utm) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom_utm, tg.geom_utm)
                GROUP BY p.proj_id, tg.taskid;
            ELSIF applied_function = 'MEDIAN' THEN
                CREATE TABLE avg_vertices_per_building_per_task AS
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                SELECT p.proj_id, tg.taskid, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ST_NPoints(tb.geom_utm) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom_utm, tg.geom_utm)
                GROUP BY p.proj_id, tg.taskid;
            ELSE
                RAISE EXCEPTION 'Unsupported applied_function: %', applied_function;
            END IF;
        ELSE
            IF applied_function = 'AVG' THEN
                CREATE TABLE avg_vertices_per_building_per_task AS
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN google_buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                SELECT p.proj_id, tg.taskid, AVG(ST_NPoints(tb.geom) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom, tg.geom)
                GROUP BY p.proj_id, tg.taskid;
            ELSIF applied_function = 'MEDIAN' THEN
                CREATE TABLE avg_vertices_per_building_per_task AS
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN google_buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                SELECT p.proj_id, tg.taskid, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ST_NPoints(tb.geom_utm) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom, tg.geom)
                GROUP BY p.proj_id, tg.taskid;
            ELSE 
                RAISE EXCEPTION 'Unsupported applied_function: %', applied_function;
            END IF;
        END IF;

        ALTER TABLE avg_vertices_per_building_per_task ADD PRIMARY KEY (proj_id, taskid, building_source, calculation);
        CREATE INDEX ON avg_vertices_per_building_per_task (proj_id);
        CREATE INDEX ON avg_vertices_per_building_per_task (taskid);
        CREATE INDEX ON avg_vertices_per_building_per_task (building_source);
        CREATE INDEX ON avg_vertices_per_building_per_task (calculation);
    ELSE
        IF source = 'OSM' THEN
            IF applied_function = 'AVG' THEN
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                INSERT INTO avg_vertices_per_building_per_task (proj_id, taskid, avg_vertices, buildings_count, building_source, calculation)
                SELECT p.proj_id, tg.taskid, AVG(ST_NPoints(tb.geom_utm) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom_utm, tg.geom_utm)
                GROUP BY p.proj_id, tg.taskid
                ON CONFLICT (proj_id, taskid, building_source, calculation) DO UPDATE SET
                    avg_vertices = EXCLUDED.avg_vertices,
                    buildings_count = EXCLUDED.buildings_count,
                    calculation = EXCLUDED.calculation;
            ELSIF applied_function = 'MEDIAN' THEN
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                INSERT INTO avg_vertices_per_building_per_task (proj_id, taskid, avg_vertices, buildings_count, building_source, calculation)
                SELECT p.proj_id, tg.taskid, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ST_NPoints(tb.geom_utm) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom_utm, tg.geom_utm)
                GROUP BY p.proj_id, tg.taskid
                ON CONFLICT (proj_id, taskid, building_source, calculation) DO UPDATE SET
                    avg_vertices = EXCLUDED.avg_vertices,
                    buildings_count = EXCLUDED.buildings_count,
                    calculation = EXCLUDED.calculation;
            ELSE
                RAISE EXCEPTION 'Unsupported applied_function: %', applied_function;
            END IF;
        ELSE
            IF applied_function = 'AVG' THEN
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN google_buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                INSERT INTO avg_vertices_per_building_per_task (proj_id, taskid, avg_vertices, buildings_count, building_source, calculation)
                SELECT p.proj_id, tg.taskid, AVG(ST_NPoints(tb.geom) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom, tg.geom)
                GROUP BY p.proj_id, tg.taskid
                ON CONFLICT (proj_id, taskid, building_source, calculation)
                DO UPDATE SET
                    avg_vertices = EXCLUDED.avg_vertices,
                    buildings_count = EXCLUDED.buildings_count,
                    calculation = EXCLUDED.calculation;
            ELSIF applied_function = 'MEDIAN' THEN
                WITH temp_buildings AS MATERIALIZED (
                    SELECT b.*
                    FROM temp_project_ids p
                    JOIN google_buildings b ON b.project_id = p.proj_id
                ), temp_grids AS MATERIALIZED (
                    SELECT g.*
                    FROM temp_project_ids p
                    JOIN grids g ON g.project_id = p.proj_id
                )
                INSERT INTO avg_vertices_per_building_per_task (proj_id, taskid, avg_vertices, buildings_count, building_source, calculation)
                SELECT p.proj_id, tg.taskid, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ST_NPoints(tb.geom) - 1) AS avg_vertices, COUNT(tb.*) AS buildings_count, source AS building_source, applied_function AS calculation
                FROM temp_project_ids p
                JOIN temp_grids tg ON tg.project_id = p.proj_id
                LEFT JOIN temp_buildings tb ON tb.project_id = p.proj_id AND ST_Intersects(tb.geom, tg.geom)
                GROUP BY p.proj_id, tg.taskid
                ON CONFLICT (proj_id, taskid, building_source, calculation)
                DO UPDATE SET
                    avg_vertices = EXCLUDED.avg_vertices,
                    buildings_count = EXCLUDED.buildings_count,
                    calculation = EXCLUDED.calculation;
            ELSE
                RAISE EXCEPTION 'Unsupported applied_function: %', applied_function;
            END IF;
        END IF;
    END IF;
    CALL raise_notice('Average number of vertices per building per task calculated');

    -- Update the selected projects to indicate that they have been processed
    IF source = 'OSM' THEN
        UPDATE selected_projects
        SET indicator_cons = indicator_cons + 1
        WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
        AND typename = 'BUILDINGS';
    ELSE
        UPDATE selected_projects
        SET indicator_cons_ai = indicator_cons_ai + 1
        WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
        AND typename = 'BUILDINGS';
    END IF;

    -- Cleanup
    DROP TABLE temp_project_ids;
END $$;