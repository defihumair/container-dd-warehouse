:on error exit
:r /repo/sql/00_setup/setup.sql
:r /repo/sql/01_raw/01_etl_control_tables.sql
:r /repo/sql/01_raw/02_raw_tables.sql
:r /repo/sql/04_procedures/raw_load_event_file.sql
:r /repo/sql/04_procedures/raw_load_reference_files.sql
:r /repo/sql/02_stg/01_stg_tables.sql
:r /repo/sql/04_procedures/stg_load_reference_data.sql
:r /repo/sql/04_procedures/stg_load_container_event.sql
:r /repo/sql/03_dw/01_dw_tables.sql
:r /repo/sql/04_procedures/dw_load_dimensions.sql
:r /repo/sql/04_procedures/dw_load_fact_container_event.sql
:r /repo/sql/04_procedures/dw_load_dd_charge.sql
:r /repo/sql/05_dq_checks/01_dq_objects.sql
:r /repo/sql/04_procedures/dq_run_checks.sql
:r /repo/sql/04_procedures/etl_run_transform.sql
