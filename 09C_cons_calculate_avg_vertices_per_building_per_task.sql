DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------------------------';
    RAISE NOTICE '-- 09C_cons_calculate_avg_vertices_per_building_per_task.sql --';
    RAISE NOTICE '---------------------------------------------------------------';

    -- Get 10% of the selected projects
	CALL raise_notice('Selecting projects');
    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_project_ids') THEN
        DROP TABLE temp_project_ids;
    END IF;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT proj_id, typename
	FROM selected_projects
	WHERE indicator_cons = 8 AND typename = 'BUILDINGS'
	ORDER BY proj_id
	--LIMIT (SELECT COUNT(*) * 0.0025 FROM selected_projects);
	LIMIT 10;
	CALL raise_notice('Projects selected');

    -- Calculate the average number of vertices of the buildings in each task
    CALL raise_notice('Calculating average number of vertices per building per task');
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'avg_vertices_per_building_per_task') THEN
        CREATE TABLE avg_vertices_per_building_per_task AS
        WITH tasks AS (
            SELECT p.proj_id, g.taskid
            FROM temp_project_ids p
            JOIN grids g ON g.project_id = p.proj_id
        )
        SELECT t.proj_id, t.taskid, avg_data.avg_vertices, avg_data.buildings_count
        FROM tasks t
        CROSS JOIN LATERAL (SELECT * FROM calculate_avg_vertices_per_building_from_tasks(t.proj_id, ARRAY[t.taskid])) AS avg_data;

        ALTER TABLE avg_vertices_per_building_per_task ADD PRIMARY KEY (proj_id, taskid);
        CREATE INDEX ON avg_vertices_per_building_per_task (proj_id);
        CREATE INDEX ON avg_vertices_per_building_per_task (taskid);
    ELSE
        INSERT INTO avg_vertices_per_building_per_task (proj_id, taskid, avg_vertices, buildings_count)
        WITH tasks AS (
            SELECT p.proj_id, g.taskid
            FROM temp_project_ids p
            JOIN grids g ON g.project_id = p.proj_id
        )
        SELECT t.proj_id, t.taskid, avg_data.avg_vertices, avg_data.buildings_count
        FROM tasks t
        CROSS JOIN LATERAL (SELECT * FROM calculate_avg_vertices_per_building_from_tasks(t.proj_id, ARRAY[t.taskid])) AS avg_data;
    END IF;
    CALL raise_notice('Average number of vertices per building per task calculated');

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cons = indicator_cons + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
    AND typename = 'BUILDINGS';

    -- Cleanup
    DROP TABLE temp_project_ids;
END $$;