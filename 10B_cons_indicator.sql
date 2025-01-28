DO $$
BEGIN
    -- Get 10% of the selected projects
	CALL raise_notice('Selecting projects');
	DROP TABLE IF EXISTS temp_project_ids;
	CREATE TEMP TABLE temp_project_ids AS
	SELECT proj_id, typename
	FROM selected_projects
	WHERE indicator_cons = 9 AND typename = 'BUILDINGS'
	ORDER BY proj_id
	--LIMIT (SELECT COUNT(*) * 0.05 FROM selected_projects);
	LIMIT 10;
	CALL raise_notice('Projects selected');

    -- Calculate the Geary's C (consistency indicator) for the selected projects
    CALL raise_notice('Calculating Geary''s C');
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'consistency') THEN
        CREATE TABLE consistency AS
        SELECT tpi.proj_id, calculate_gearys_c_for_project(tpi.proj_id) AS consistency 
        FROM temp_project_ids tpi;
    ELSE
        INSERT INTO consistency (proj_id, consistency)
        SELECT tpi.proj_id, calculate_gearys_c_for_project(tpi.proj_id) AS consistency 
        FROM temp_project_ids tpi;
    END IF;
    CALL raise_notice('Geary''s C calculated');

    -- Update the selected projects to indicate that they have been processed
    UPDATE selected_projects
    SET indicator_cons = indicator_cons + 1
    WHERE proj_id IN (SELECT proj_id FROM temp_project_ids)
    AND typename = 'BUILDINGS';

    -- Cleanup
    DROP TABLE IF EXISTS temp_project_ids;
END $$;