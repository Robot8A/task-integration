DROP FUNCTION IF EXISTS calculate_avg_vertices_per_building_from_tasks;
CREATE FUNCTION calculate_avg_vertices_per_building_from_tasks(project_id INT, task_ids INT[])
RETURNS TABLE(
    avg_vertices FLOAT,
    buildings_count INT
) AS $$
DECLARE
    vertices_sum FLOAT;
BEGIN
    SELECT SUM(ST_NPoints(geom) - 1) INTO vertices_sum
    FROM get_buildings_from_tasks(project_id, task_ids);

    SELECT COUNT(*) INTO buildings_count
    FROM get_buildings_from_tasks(project_id, task_ids);

    avg_vertices := vertices_sum / NULLIF(buildings_count, 0);

    RETURN QUERY SELECT avg_vertices, buildings_count;
END $$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS calculate_gearys_c_for_project;
CREATE FUNCTION calculate_gearys_c_for_project(project_id INT)
RETURNS FLOAT AS $$
DECLARE
    task RECORD;
    adjacent_task RECORD;
    total_weight FLOAT := 0;
    sum_of_squared_differences FLOAT := 0;
    sum_of_squared_mean_differences FLOAT := 0;
    mean_vertices FLOAT;
    n INT := 0;
BEGIN
    -- Calculate the mean of avg_vertices for the project
    SELECT AVG(COALESCE(avgpbpt.avg_vertices, 0)) INTO mean_vertices
    FROM avg_vertices_per_building_per_task avgpbpt
    WHERE avgpbpt.proj_id = calculate_gearys_c_for_project.project_id;

    -- Loop through each task in the project
    FOR task IN
        SELECT avgpbpt.taskid, COALESCE(avgpbpt.avg_vertices, 0) AS avg_vertices, proj_id
        FROM avg_vertices_per_building_per_task avgpbpt
        WHERE avgpbpt.proj_id = calculate_gearys_c_for_project.project_id
    LOOP
        -- Increment the task count
        n := n + 1;

        -- Calculate the sum of squared differences from the mean
        sum_of_squared_mean_differences := sum_of_squared_mean_differences + 
                (task.avg_vertices - mean_vertices) *
                (task.avg_vertices - mean_vertices);

        -- Loop through each adjacent task
        FOR adjacent_task IN
            SELECT ata.adjacent_task_id, COALESCE(avgpbpt.avg_vertices, 0) AS avg_vertices
            FROM adjacent_tasks ata
            JOIN avg_vertices_per_building_per_task avgpbpt
            ON ata.adjacent_task_id = avgpbpt.taskid
            WHERE ata.task_id = task.taskid AND ata.proj_id = task.proj_id AND avgpbpt.proj_id = task.proj_id
        LOOP
            -- Calculate the total weight
            total_weight := total_weight + 1;

            -- Calculate the squared difference of avg_vertices
            sum_of_squared_differences := sum_of_squared_differences + 
                (task.avg_vertices - adjacent_task.avg_vertices) * 
                (task.avg_vertices - adjacent_task.avg_vertices);
        END LOOP;
    END LOOP;

    -- Calculate the variance of avg_vertices for the project
    IF n > 1 THEN

        -- Calculate Geary's C
        IF total_weight > 0 THEN
            RETURN ((n - 1) * sum_of_squared_differences) / (2 * total_weight * sum_of_squared_mean_differences);
        ELSE
            RETURN NULL;
        END IF;
    ELSE
        RETURN NULL;
    END IF;
END $$ LANGUAGE plpgsql;
