DO $$
DECLARE
    building_source TEXT := 'OSM';
BEGIN
    -- Get 10% of the selected projects
	CALL raise_notice('Selecting projects');
	IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_project_ids') THEN
        DROP TABLE temp_project_ids;
    END IF;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT proj_id, typename
	FROM selected_projects
	WHERE (building_source = 'OSM' AND indicator_cons = 9 OR building_source != 'OSM' AND indicator_cons_ai = 9)
    AND typename = 'BUILDINGS'
	ORDER BY proj_id
	;
    --LIMIT (SELECT COUNT(*) * 0.05 FROM selected_projects);
	--LIMIT 1000;
	CALL raise_notice('Projects selected');

    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'null_strategies') THEN
        DROP TABLE null_strategies;
    END IF;
    CREATE TEMP TABLE null_strategies AS
    SELECT 'EXCLUDE' AS null_strategy
    UNION
    SELECT 'SET_TO_ZERO' AS null_strategy;

    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'weight_strategies') THEN
        DROP TABLE weight_strategies;
    END IF;
    CREATE TEMP TABLE weight_strategies AS
    SELECT 'BUILDING_COUNT' AS weight_strategy
    UNION
    SELECT 'BUILDING_COUNT_LOG' AS weight_strategy
    UNION
    SELECT 'EQUAL' AS weight_strategy;

    -- Calculate the Geary's C (consistency indicator) for the selected projects
    CALL raise_notice('Calculating Geary''s C');
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'consistency') THEN
        CREATE TABLE consistency AS
        SELECT tpi.proj_id, calculate_gearys_c_for_project(tpi.proj_id, ns.null_strategy, ws.weight_strategy, building_source) AS consistency, ns.null_strategy, ws.weight_strategy, building_source
        FROM temp_project_ids tpi
        JOIN null_strategies ns ON TRUE
        JOIN weight_strategies ws ON TRUE;
    ELSE
        INSERT INTO consistency (proj_id, consistency, null_strategy, weight_strategy, building_source)
        SELECT tpi.proj_id, calculate_gearys_c_for_project(tpi.proj_id, ns.null_strategy, ws.weight_strategy, building_source) AS consistency, ns.null_strategy, ws.weight_strategy, building_source
        FROM temp_project_ids tpi
        JOIN null_strategies ns ON TRUE
        JOIN weight_strategies ws ON TRUE;
    END IF;
    CALL raise_notice('Geary''s C calculated');

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cons = indicator_cons + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
    AND typename = 'BUILDINGS';

    -- Cleanup
    DROP TABLE IF EXISTS temp_project_ids;
    DROP TABLE IF EXISTS null_strategies;
    DROP TABLE IF EXISTS weight_strategies;
END $$;