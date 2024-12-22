DO $$ 
DECLARE
    row_partition_threshold integer := 1000000;
    current_row_sum integer := 0;
    create_partition boolean := FALSE;
    project_from integer := 0;
    project_to integer;
    current_project_id integer;
BEGIN
    RAISE NOTICE '======================================';
    RAISE NOTICE 'Creating partition table for grids';

    CREATE TEMP TABLE rows_per_project AS
    SELECT 
        project_id,
        COUNT(*) AS number_of_rows
    FROM grids_pre_partition
    GROUP BY project_id
    ORDER BY project_id;

    ALTER TABLE grids_pre_partition DROP CONSTRAINT grids_pre_partition_pkey;
    ALTER TABLE grids_pre_partition DROP COLUMN gid;
    ALTER TABLE grids_pre_partition DROP COLUMN lockedby;
    ALTER TABLE grids_pre_partition DROP COLUMN mappedby;
    ALTER TABLE grids_pre_partition DROP COLUMN taskissquare;
    ALTER TABLE grids_pre_partition DROP COLUMN taskstatus;
    ALTER TABLE grids_pre_partition DROP COLUMN taskx;
    ALTER TABLE grids_pre_partition DROP COLUMN tasky;
    ALTER TABLE grids_pre_partition DROP COLUMN taskzoom;
    ALTER TABLE grids_pre_partition ADD CONSTRAINT grids_pre_partition_pkey PRIMARY KEY (project_id, taskid);

    CREATE TABLE grids (LIKE grids_pre_partition INCLUDING ALL) 
    PARTITION BY RANGE (project_id);

    CREATE TABLE mockup_polygon_grids (
        project_id INT,
        taskid INT,
        geom geometry,
        percentage_covered DOUBLE PRECISION
    )
    PARTITION BY RANGE (project_id);
    
    -- Iterate over rows_per_project until we reach the threshold, then do partitioning
    FOR current_project_id IN SELECT project_id FROM rows_per_project
    LOOP
        IF create_partition THEN
            project_to := current_project_id;
            RAISE NOTICE 'Creating partition for projects % to %', project_from, project_to;
            EXECUTE 'CREATE TABLE grids_' || project_from || '_' || project_to || ' PARTITION OF grids FOR VALUES FROM (' || project_from || ') TO (' || project_to || ')';
            EXECUTE 'CREATE TABLE mockup_polygon_grids_' || project_from || '_' || project_to || ' PARTITION OF mockup_polygon_grids FOR VALUES FROM (' || project_from || ') TO (' || project_to || ')';
            project_from := project_to;
            create_partition := FALSE;
            current_row_sum := 0;
        END IF;

        current_row_sum := current_row_sum + (SELECT number_of_rows FROM rows_per_project WHERE project_id = current_project_id);
        
        IF current_row_sum >= row_partition_threshold THEN
            create_partition := TRUE;
        END IF;
    END LOOP;

    DROP TABLE rows_per_project;

    -- Create partition for the remaining projects
    RAISE NOTICE 'Creating partition for projects % to MAXVALUE', project_from;
    EXECUTE 'CREATE TABLE grids_' || project_from || '_MAX PARTITION OF grids FOR VALUES FROM (' || project_from || ') TO (MAXVALUE)';
    EXECUTE 'CREATE TABLE mockup_polygon_grids_' || project_from || '_MAX PARTITION OF mockup_polygon_grids FOR VALUES FROM (' || project_from || ') TO (MAXVALUE)';
    project_from := 0;
    create_partition := FALSE;
    current_row_sum := 0;

    -- Populate the partitioned tables, and fixing the geometry
    RAISE NOTICE 'Populating partitioned tables';
    INSERT INTO grids (project_id, taskid, geom) SELECT project_id, taskid, fix_geometry(geom) FROM grids_pre_partition;

    -- Alter grids table to add an extra geometry column, with the geom in UTM
    ALTER TABLE grids ADD COLUMN geom_utm geometry(Geometry);
    UPDATE
        grids
    SET
        geom_utm = ST_Transform(geom, get_utm_zone(project_id));

    RAISE NOTICE 'Dropping the original table';
    DROP TABLE grids_pre_partition;
    RAISE NOTICE 'DONE';

    RAISE NOTICE '======================================';
    RAISE NOTICE 'Creating partition table for buildings';

    CREATE TEMP TABLE rows_per_project AS
    SELECT 
        project_id,
        COUNT(*) AS number_of_rows
    FROM buildings_pre_partition
    GROUP BY project_id
    ORDER BY project_id;

    ALTER TABLE buildings_pre_partition DROP CONSTRAINT buildings_pre_partition_pkey;
    ALTER TABLE buildings_pre_partition DROP COLUMN gid;
    ALTER TABLE buildings_pre_partition DROP COLUMN name;
    ALTER TABLE buildings_pre_partition DROP COLUMN building;
    ALTER TABLE buildings_pre_partition DROP COLUMN "building:levels";
    ALTER TABLE buildings_pre_partition DROP COLUMN "building:materials";
    ALTER TABLE buildings_pre_partition DROP COLUMN "addr:full";
    ALTER TABLE buildings_pre_partition DROP COLUMN "addr:housenumber";
    ALTER TABLE buildings_pre_partition DROP COLUMN "addr:street";
    ALTER TABLE buildings_pre_partition DROP COLUMN "addr:city";
    ALTER TABLE buildings_pre_partition DROP COLUMN office;
    ALTER TABLE buildings_pre_partition DROP COLUMN source;
    ALTER TABLE buildings_pre_partition DROP COLUMN osm_type;
    ALTER TABLE buildings_pre_partition ADD COLUMN geom_utm geometry(Geometry);
    ALTER TABLE buildings_pre_partition ADD CONSTRAINT buildings_pre_partition_pkey PRIMARY KEY (project_id, osm_id);

    CREATE TABLE buildings (LIKE buildings_pre_partition INCLUDING ALL) 
    PARTITION BY RANGE (project_id);
    
    -- Iterate over rows_per_project until we reach the threshold, then do partitioning
    FOR current_project_id IN SELECT project_id FROM rows_per_project
    LOOP
        IF create_partition THEN
            project_to := current_project_id;
            RAISE NOTICE 'Creating partition for projects % to %', project_from, project_to;
            EXECUTE 'CREATE TABLE buildings_' || project_from || '_' || project_to || ' PARTITION OF buildings FOR VALUES FROM (' || project_from || ') TO (' || project_to || ')';
            project_from := project_to;
            create_partition := FALSE;
            current_row_sum := 0;
        END IF;

        current_row_sum := current_row_sum + (SELECT number_of_rows FROM rows_per_project WHERE project_id = current_project_id);
        
        IF current_row_sum >= row_partition_threshold THEN
            create_partition := TRUE;
        END IF;
    END LOOP;

    DROP TABLE rows_per_project;

    -- Create partition for the remaining projects
    RAISE NOTICE 'Creating partition for projects % to MAXVALUE', project_from;
    EXECUTE 'CREATE TABLE buildings_' || project_from || '_MAX PARTITION OF buildings FOR VALUES FROM (' || project_from || ') TO (MAXVALUE)';
    project_from := 0;
    create_partition := FALSE;
    current_row_sum := 0;

    -- Populate the partitioned tables
    RAISE NOTICE 'Populating partitioned tables';
    INSERT INTO buildings (project_id, osm_id, geom, geom_utm) SELECT bpp.project_id, bpp.osm_id, NULL, ST_Transform(bpp.geom, get_utm_zone(bpp.project_id)) FROM buildings_pre_partition bpp;

    -- Alter grids table to add an extra geometry column, with the geom in UTM
    -- ALTER TABLE buildings ADD COLUMN geom_utm geometry(Geometry);
    -- UPDATE
    --     buildings
    -- SET
    --     geom_utm = ST_Transform(geom, get_utm_zone(project_id));

    RAISE NOTICE 'Dropping the original table';
    DROP TABLE buildings_pre_partition;
    RAISE NOTICE 'DONE';

    RAISE NOTICE '======================================';
    RAISE NOTICE 'Creating partition table for roads';

    CREATE TEMP TABLE rows_per_project AS
    SELECT 
        project_id,
        COUNT(*) AS number_of_rows
    FROM roads_pre_partition
    GROUP BY project_id
    ORDER BY project_id;

    ALTER TABLE roads_pre_partition DROP CONSTRAINT roads_pre_partition_pkey;
    ALTER TABLE roads_pre_partition DROP COLUMN gid;
    ALTER TABLE roads_pre_partition ADD CONSTRAINT roads_pre_partition_pkey PRIMARY KEY (project_id, osm_id);

    CREATE TABLE roads (LIKE roads_pre_partition INCLUDING ALL) 
    PARTITION BY RANGE (project_id);
    
    -- Iterate over rows_per_project until we reach the threshold, then do partitioning
    FOR current_project_id IN SELECT project_id FROM rows_per_project
    LOOP
        IF create_partition THEN
            project_to := current_project_id;
            RAISE NOTICE 'Creating partition for projects % to %', project_from, project_to;
            EXECUTE 'CREATE TABLE roads_' || project_from || '_' || project_to || ' PARTITION OF roads FOR VALUES FROM (' || project_from || ') TO (' || project_to || ')';
            project_from := project_to;
            create_partition := FALSE;
            current_row_sum := 0;
        END IF;

        current_row_sum := current_row_sum + (SELECT number_of_rows FROM rows_per_project WHERE project_id = current_project_id);
        
        IF current_row_sum >= row_partition_threshold THEN
            create_partition := TRUE;
        END IF;
    END LOOP;

    DROP TABLE rows_per_project;

    -- Create partition for the remaining projects
    RAISE NOTICE 'Creating partition for projects % to MAXVALUE', project_from;
    EXECUTE 'CREATE TABLE roads_' || project_from || '_MAX PARTITION OF roads FOR VALUES FROM (' || project_from || ') TO (MAXVALUE)';
    project_from := 0;
    create_partition := FALSE;
    current_row_sum := 0;

    -- Populate the partitioned tables
    RAISE NOTICE 'Populating partitioned tables';
    INSERT INTO roads SELECT * FROM roads_pre_partition;

    RAISE NOTICE 'Dropping the original table';
    DROP TABLE roads_pre_partition;
    RAISE NOTICE 'DONE';
END $$;