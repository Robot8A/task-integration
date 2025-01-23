CREATE EXTENSION postgis;

CREATE TABLE IF NOT EXISTS utm_zones (
    utm_epsg INT,
    project_id INT
);