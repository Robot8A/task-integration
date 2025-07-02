CREATE INDEX ON projects (id);
CREATE INDEX ON buildings USING GIST(geom_utm);