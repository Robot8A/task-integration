-- Remove the grid data from non-selected projects
DELETE FROM grids
WHERE project_id NOT IN (
    SELECT proj_id
    FROM selected_projects
);

-- Remove the road data from non-selected projects
DELETE FROM roads
WHERE project_id NOT IN (
    SELECT proj_id
    FROM selected_projects
);

-- Remove the building data from non-selected projects
DELETE FROM buildings
WHERE project_id NOT IN (
    SELECT proj_id
    FROM selected_projects
);

-- Update the project statuses
UPDATE selected_projects
SET indicator_cont_dup = indicator_cont_dup + 1,
    indicator_cons = indicator_cons + 1
WHERE indicator_cont_dup = 6 AND indicator_cons = 6;