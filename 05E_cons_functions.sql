-- DROP FUNCTION IF EXISTS calculate_avg_vertices_per_building_from_tasks;
-- CREATE FUNCTION calculate_avg_vertices_per_building_from_tasks(project_id INT, task_ids INT[])
-- RETURNS TABLE(
--     avg_vertices FLOAT,
--     buildings_count INT
-- ) AS $$
-- DECLARE
--     vertices_sum FLOAT;
-- BEGIN
--     SELECT SUM(ST_NPoints(geom)) INTO vertices_sum
--     FROM get_buildings_from_tasks(project_id, task_ids);

--     SELECT COUNT(*) INTO buildings_count
--     FROM get_buildings_from_tasks(project_id, task_ids);

--     avg_vertices := (vertices_sum - buildings_count) / NULLIF(buildings_count, 0);

--     RETURN QUERY SELECT avg_vertices, buildings_count;
-- END $$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS calculate_gearys_c_for_project;
CREATE FUNCTION calculate_gearys_c_for_project(
    project_id INT,
    null_strategy TEXT DEFAULT 'EXCLUDE',
    weight_strategy TEXT DEFAULT 'BUILDING_COUNT',
    building_source TEXT DEFAULT 'OSM'
)
RETURNS FLOAT AS $$
DECLARE
    task RECORD;
    adjacent_task RECORD;
    current_weight FLOAT;
    total_weight FLOAT := 0;
    sum_of_squared_differences FLOAT := 0;
    sum_of_squared_mean_differences FLOAT := 0;
    mean_vertices FLOAT;
    n INT := 0;
BEGIN
    -- Calculate the mean of avg_vertices for the project
    SELECT AVG(COALESCE(avgpbpt.avg_vertices, 0)) INTO mean_vertices
    FROM avg_vertices_per_building_per_task avgpbpt
    WHERE avgpbpt.proj_id = calculate_gearys_c_for_project.project_id
    AND (null_strategy != 'EXCLUDE' OR avgpbpt.avg_vertices IS NOT NULL)
    AND avgpbpt.building_source = calculate_gearys_c_for_project.building_source;

    -- Loop through each task in the project
    FOR task IN
        SELECT avgpbpt.taskid, COALESCE(avgpbpt.avg_vertices, 0) AS avg_vertices, proj_id
        FROM avg_vertices_per_building_per_task avgpbpt
        WHERE avgpbpt.proj_id = calculate_gearys_c_for_project.project_id
        AND (null_strategy != 'EXCLUDE' OR avgpbpt.avg_vertices IS NOT NULL)  
        AND avgpbpt.building_source = calculate_gearys_c_for_project.building_source
    LOOP
        
        -- Increment the task count
        n := n + 1;

        -- Calculate the sum of squared differences from the mean
        sum_of_squared_mean_differences := sum_of_squared_mean_differences + 
                (task.avg_vertices - mean_vertices) *
                (task.avg_vertices - mean_vertices);

        -- Loop through each adjacent task
        FOR adjacent_task IN
            SELECT ata.adjacent_task_id, COALESCE(avgpbpt.avg_vertices, 0) AS avg_vertices, avgpbpt.buildings_count
            FROM adjacent_tasks ata
            JOIN avg_vertices_per_building_per_task avgpbpt
            ON ata.adjacent_task_id = avgpbpt.taskid
            WHERE ata.task_id = task.taskid AND ata.proj_id = task.proj_id AND avgpbpt.proj_id = task.proj_id
            AND (null_strategy != 'EXCLUDE' OR avgpbpt.avg_vertices IS NOT NULL)
            AND avgpbpt.building_source = calculate_gearys_c_for_project.building_source
        LOOP
            -- Calculate the total weight
            IF weight_strategy = 'BUILDING_COUNT' THEN
                current_weight := adjacent_task.buildings_count;
            ELSIF weight_strategy = 'BUILDING_COUNT_LOG' THEN
                current_weight := LOG(adjacent_task.buildings_count + 1);
            ELSE
                current_weight := 1;
            END IF;
            total_weight := total_weight + current_weight;

            -- Calculate the squared difference of avg_vertices
            sum_of_squared_differences := sum_of_squared_differences + 
                current_weight *
                (task.avg_vertices - adjacent_task.avg_vertices) * 
                (task.avg_vertices - adjacent_task.avg_vertices);
        END LOOP;
    END LOOP;

    -- Calculate the variance of avg_vertices for the project
    IF n > 1 THEN

        -- Calculate Geary's C
        IF total_weight > 0 AND sum_of_squared_mean_differences > 0 THEN
            RETURN ((n - 1) * sum_of_squared_differences) / (2 * total_weight * sum_of_squared_mean_differences);
        ELSE
            RETURN NULL;
        END IF;
    ELSE
        RETURN NULL;
    END IF;
END $$ LANGUAGE plpgsql;
