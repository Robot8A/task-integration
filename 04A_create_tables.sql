---CREATE TABLE IF NOT EXISTS mockup_grids (
---    project_id INT,
---    geom geometry
---);

CREATE TABLE IF NOT EXISTS mockup_polygon_grids (
    project_id INT,
    taskid INT,
    geom geometry,
    percentage_covered DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS nonconnecting_nodes (
    project_id INT,
    geom geometry,
    point_type TEXT
);

CREATE TABLE IF NOT EXISTS continuation (
    project_id INT,
    grid_type TEXT,
    shrink_distance DOUBLE PRECISION,
    shrink_type TEXT,
    nodes_in_shrunk_grids BIGINT,
    nodes_in_border_buffer BIGINT,
    area_of_shrunk_grids DOUBLE PRECISION,
    area_of_border_buffer DOUBLE PRECISION,
    nodes_per_area_shrunk_grids DOUBLE PRECISION,
    nodes_per_area_border_buffer DOUBLE PRECISION,
    PRIMARY KEY (project_id, grid_type, shrink_distance, shrink_type)
);

CREATE TABLE IF NOT EXISTS buildings_utm (
    osm_id INT,
    geom GEOMETRY,
    project_id INT
);

CREATE TABLE IF NOT EXISTS geometry_consistency (
    project_id INT,
    task_id INT,
    average_vertices_original FLOAT,
    average_vertices_simplified FLOAT,
    average_simplified_area_covered_from_original FLOAT,
    number_of_buildings INT,
    task_area FLOAT,
    tolerance_used FLOAT,
    PRIMARY KEY (project_id, task_id, tolerance_used)
);

CREATE TABLE IF NOT EXISTS geometry_consistency_adjacent (
    project_id INT,
    task_id INT,
    neighbouring_average_vertices_original FLOAT,
    neighbouring_average_vertices_simplified FLOAT,
    neighbouring_average_simplified_area_covered_from_original FLOAT,
    neighbouring_number_of_buildings INT,
    number_of_neighbouring_tasks INT,
    neighbouring_tasks_area FLOAT,
    tolerance_used FLOAT,
    PRIMARY KEY (project_id, task_id, tolerance_used)
);
