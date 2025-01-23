DO $$
BEGIN
    -- Get 10% of the selected projects
	CALL raise_notice('Selecting projects');
	DROP TABLE IF EXISTS temp_project_ids_08B;
	CREATE TEMP TABLE temp_project_ids_08B AS
	SELECT proj_id, typename
	FROM selected_projects
	WHERE indicator_cons = 7 AND typename = 'BUILDINGS'
	ORDER BY proj_id
	--LIMIT (SELECT COUNT(*) * 0.0025 FROM selected_projects);
	LIMIT 10;
	CALL raise_notice('Projects selected');


    -- Calculate task adjacency
    CALL raise_notice('Calculating task adjacency');
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'adjacent_tasks') THEN
        CREATE TABLE adjacent_tasks AS
        WITH tasks AS (
            SELECT p.proj_id, g.taskid, ST_MakeValid(g.geom) AS geom
            FROM temp_project_ids_08B p
            JOIN grids g ON g.project_id = p.proj_id
        )
        SELECT t1.proj_id, t1.taskid AS task_id, t2.taskid AS adjacent_task_id
        FROM tasks t1
        JOIN tasks t2 ON ST_Touches(t1.geom, t2.geom)
        WHERE t1.taskid <> t2.taskid;
        CREATE INDEX ON adjacent_tasks (proj_id);
        CREATE INDEX ON adjacent_tasks (task_id);
        CREATE INDEX ON adjacent_tasks (adjacent_task_id);
    ELSE
        INSERT INTO adjacent_tasks (proj_id, task_id, adjacent_task_id)
        WITH tasks AS (
            SELECT p.proj_id, g.taskid, ST_MakeValid(g.geom) AS geom
            FROM temp_project_ids_08B p
            JOIN grids g ON g.project_id = p.proj_id
        )
        SELECT t1.proj_id, t1.taskid AS task_id, t2.taskid AS adjacent_task_id
        FROM tasks t1
        JOIN tasks t2 ON ST_Touches(t1.geom, t2.geom)
        WHERE t1.taskid <> t2.taskid;
    END IF;
    CALL raise_notice('Task adjacency calculated');

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cons = indicator_cons + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids_08B)
    AND typename = 'BUILDINGS';

    -- Cleanup
    DROP TABLE IF EXISTS temp_project_ids_08B;
END $$;