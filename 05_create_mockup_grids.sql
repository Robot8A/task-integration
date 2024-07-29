CREATE TABLE IF NOT EXISTS mockup_grids (
    project_id INT,
    geom geometry,
    PRIMARY KEY (project_id, geom)
);

WITH proj_ids AS (
	SELECT proj_id AS ids
	FROM public.mapping_types
	WHERE typename = 'ROADS'
    AND project_has_fully_adjacent_cells(proj_id)
    OFFSET 0
	LIMIT 10
)
INSERT INTO mockup_grids (project_id, geom)
SELECT proj_id AS project_id, geom
FROM generate_mockup_grid(proj_id)
ON CONFLICT DO NOTHING;
