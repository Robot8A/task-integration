DROP FUNCTION IF EXISTS calculate_avg_vertices_per_building_from_tasks;
CREATE FUNCTION calculate_avg_vertices_per_building_from_tasks(project_id INT, task_ids INT[])
RETURNS TABLE(
    avg_vertices FLOAT,
    buildings_count INT
) AS $$
DECLARE
    vertices_sum FLOAT;
BEGIN
    SELECT SUM(ST_NPoints(geom)) INTO vertices_sum
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
    mean_vertices FLOAT;
    total_weight FLOAT := 0;
    sum_of_squared_differences FLOAT := 0;
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

    -- Loop through each task in the project
    FOR task IN
        SELECT task_id, avg_vertices
        FROM avg_vertices_per_building_per_task
        WHERE project_id = calculate_gearys_c_for_project.project_id
    LOOP
        -- Loop through each adjacent task
        FOR adjacent_task IN
            SELECT adjacent_task_id, avg_vertices
            FROM task_adjacency
            JOIN avg_vertices_per_building_per_task
            ON task_adjacency.adjacent_task_id = avg_vertices_per_building_per_task.task_id
            WHERE task_adjacency.task_id = task.task_id
        LOOP
            -- Calculate the weight
            total_weight := total_weight + 1;

            -- Calculate the squared difference of avg_vertices
            sum_of_squared_differences := sum_of_squared_differences + 
                (task.avg_vertices - adjacent_task.avg_vertices) * 
                (task.avg_vertices - adjacent_task.avg_vertices);
        END LOOP;
    END LOOP;
    
    -- Calculate Geary's C
    RETURN (n - 1) * sum_of_squared_differences / (2 * total_weight * mean_vertices);
END $$ LANGUAGE plpgsql;
