
{% macro teradata__list_schemas(database) %}
    {% call statement('list_schemas', fetch_result=True, auto_begin=False) -%}
        select distinct DatabaseName as schema_name
        from {{ information_schema_name(database) }}.DatabasesV
    {%- endcall %}

    {{ return(load_result('list_schemas').table) }}
{% endmacro %}

{% macro teradata__create_schema(relation) -%}
    {%- call statement('create_database') -%}
        CREATE DATABASE {{ relation.without_identifier() }}
            AS PERMANENT = 60e6, -- 60MB
            SPOOL = 120e6; -- 120MB
    {%- endcall -%}

    {%- call statement('grant_create_proc') -%}
        GRANT CREATE PROCEDURE ON {{ relation.without_identifier() }} TO dbc
    {%- endcall -%}

    {%- call statement('create_proc_drop_relation') -%}
        REPLACE PROCEDURE {{ relation.without_identifier() }}.dbt_drop_relation_if_exists(
          IN relation_type varchar(10),
          IN full_name varchar(256)
        )
        BEGIN
          DECLARE sql_stmt VARCHAR(500)  CHARACTER SET Unicode;
          DECLARE msg VARCHAR(400) CHARACTER SET Unicode;

          DECLARE exit HANDLER FOR SqlException
          BEGIN
            IF SqlCode = 3807 THEN SET msg = full_name || ' does not exist.';
            ELSEIF SqlCode = 3853 THEN SET msg = full_name || ' is not a table.';
            ELSEIF SqlCode = 3854 THEN SET msg = full_name || ' is not a view.';
            ELSE
              RESIGNAL;
            END IF;
          END;

          SET sql_stmt = 'DROP ' || relation_type || ' ' || full_name || ';';
          EXECUTE IMMEDIATE sql_stmt;
        END;
    {%- endcall -%}
{% endmacro %}

{% macro teradata__drop_schema(relation) -%}
    {%- call statement('delete_database') -%}
        delete database {{ relation.without_identifier() }};
    {% endcall %}
    {%- call statement('drop_database') -%}
        drop database {{ relation.without_identifier() }};
    {% endcall %}
{% endmacro %}

{% macro teradata__drop_relation(relation) -%}
    {% call statement('drop_relation', auto_begin=False) -%}
        call {{ relation.schema }}.dbt_drop_relation_if_exists('{{ relation.type }}', '{{ relation }}');
    {%- endcall %}
{% endmacro %}

{% macro teradata__truncate_relation(relation) -%}
    {% call statement('truncate_relation') -%}
      delete {{ relation }} all
    {%- endcall %}
{% endmacro %}

{% macro teradata__create_table_as(temporary, relation, sql) -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {{ sql_header if sql_header is not none }}
  create table
    {{ relation.include(database=False) }}
  as (
    {{ sql }}
  )
  with data
{% endmacro %}

{% macro teradata__create_view_as(relation, sql) -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {{ sql_header if sql_header is not none }}
  replace view {{ relation.include(database=False) }} as (
    {{ sql }}
  )
{% endmacro %}

{% macro teradata__current_timestamp() -%}
  current_timestamp
{%- endmacro %}

{% macro teradata__rename_relation(from_relation, to_relation) -%}
  {#
    Teradata rename fails when the relation already exists, so a 2-step process is needed:
    1. Drop the existing relation
    2. Rename the new relation to the existing relation
  #}
  {% call statement('drop_relation') %}
    call {{ to_relation.schema }}.dbt_drop_relation_if_exists('{{ to_relation.type }}', '{{ to_relation }}');
  {% endcall %}
  {% call statement('rename_relation') %}
    rename {{ to_relation.type }} {{ from_relation }} to {{ to_relation }}
  {% endcall %}
{% endmacro %}

{% macro teradata__check_schema_exists(database, schema) -%}
    {# no-op #}
    {# see TeradataAdapter.check_schema_exists() #}
{% endmacro %}

{% macro teradata__get_columns_in_relation(relation) -%}
    {% call statement('get_columns_in_relation', fetch_result=True) %}
    select
      ColumnsV.ColumnName as "column",
      case
        when ColumnsV.ColumnType = '++' then 'TD_ANYTYPE'
        when ColumnsV.ColumnType = 'A1' then 'ARRAY'
        when ColumnsV.ColumnType = 'AN' then 'ARRAY'
        when ColumnsV.ColumnType = 'I8' then 'BIGINT'
        when ColumnsV.ColumnType = 'BO' then 'BINARY LARGE OBJECT'
        when ColumnsV.ColumnType = 'BF' then 'BYTE'
        when ColumnsV.ColumnType = 'BV' then 'BYTE VARYING'
        when ColumnsV.ColumnType = 'I1' then 'BYTEINT'
        when ColumnsV.ColumnType = 'CF' then 'CHARACTER'
        when ColumnsV.ColumnType = 'CV' then 'CHARACTER'
        when ColumnsV.ColumnType = 'CO' then 'CHARACTER LARGE OBJECT'
        when ColumnsV.ColumnType = 'D' then 'DECIMAL'
        when ColumnsV.ColumnType = 'DA' then 'DATE'
        when ColumnsV.ColumnType = 'F' then 'DOUBLE PRECISION'
        when ColumnsV.ColumnType = 'F' then 'FLOAT'
        when ColumnsV.ColumnType = 'I' then 'INTEGER'
        when ColumnsV.ColumnType = 'DY' then 'INTERVAL DAY'
        when ColumnsV.ColumnType = 'DH' then 'INTERVAL DAY TO HOUR'
        when ColumnsV.ColumnType = 'DM' then 'INTERVAL DAY TO MINUTE'
        when ColumnsV.ColumnType = 'DS' then 'INTERVAL DAY TO SECOND'
        when ColumnsV.ColumnType = 'HR' then 'INTERVAL HOUR'
        when ColumnsV.ColumnType = 'HM' then 'INTERVAL HOUR TO MINUTE'
        when ColumnsV.ColumnType = 'HS' then 'INTERVAL HOUR TO SECOND'
        when ColumnsV.ColumnType = 'MI' then 'INTERVAL MINUTE'
        when ColumnsV.ColumnType = 'MS' then 'INTERVAL MINUTE TO SECOND'
        when ColumnsV.ColumnType = 'MO' then 'INTERVAL MONTH'
        when ColumnsV.ColumnType = 'SC' then 'INTERVAL SECOND'
        when ColumnsV.ColumnType = 'YR' then 'INTERVAL YEAR'
        when ColumnsV.ColumnType = 'YM' then 'INTERVAL YEAR TO MONTH'
        when ColumnsV.ColumnType = 'N' then 'NUMBER'
        when ColumnsV.ColumnType = 'D' then 'NUMERIC'
        when ColumnsV.ColumnType = 'PD' then 'PERIOD(DATE)'
        when ColumnsV.ColumnType = 'PT' then 'PERIOD(TIME(n))'
        when ColumnsV.ColumnType = 'PZ' then 'PERIOD(TIME(n) WITH TIME ZONE)'
        when ColumnsV.ColumnType = 'PS' then 'PERIOD(TIMESTAMP(n))'
        when ColumnsV.ColumnType = 'PM' then 'PERIOD(TIMESTAMP(n) WITH TIME ZONE)'
        when ColumnsV.ColumnType = 'F' then 'REAL'
        when ColumnsV.ColumnType = 'I2' then 'SMALLINT'
        when ColumnsV.ColumnType = 'AT' then 'TIME'
        when ColumnsV.ColumnType = 'TS' then 'TIMESTAMP'
        when ColumnsV.ColumnType = 'TZ' then 'TIME WITH TIME ZONE'
        when ColumnsV.ColumnType = 'SZ' then 'TIMESTAMP WITH TIME ZONE'
        when ColumnsV.ColumnType = 'UT' then 'USER‑DEFINED TYPE'
        when ColumnsV.ColumnType = 'XM' then 'XML'
        else 'CHARACTER'
      end as dtype,
      case
        when ColumnsV.CharType = 1 then ColumnsV.ColumnLength
      end as char_size,
      ColumnsV.DecimalTotalDigits as numeric_precision,
      ColumnsV.DecimalFractionalDigits as numeric_scale,
      null as table_database,
      ColumnsV.DatabaseName as table_schema,
      ColumnsV.TableName as table_name,
      case when TablesV.TableKind = 'T' then 'table'
        when TablesV.TableKind = 'V' then 'view'
        else TablesV.TableKind
      end as table_type,
      ColumnsV.ColumnID as column_index
    from DBC.ColumnsV
    left outer join DBC.TablesV
      on ColumnsV.DatabaseName = TablesV.DatabaseName
      and ColumnsV.TableName = TablesV.TableName
    where
      TablesV.TableKind in ('T', 'V')
      and ColumnsV.DatabaseName like '{{ relation.schema }}'
      and ColumnsV.TableName like '{{ relation.identifier }}'
    order by
      ColumnsV.ColumnID
    {% endcall %}

    {% set table = load_result('get_columns_in_relation').table %}

    {{ return(sql_convert_columns_in_relation(table)) }}
{% endmacro %}

{% macro teradata__list_relations_without_caching(schema_relation) %}
  {% call statement('list_relations_without_caching', fetch_result=True) -%}
    select
      null as "database",
      TableName as name,
      DatabaseName as "schema",
      case when TableKind = 'T' then 'table'
         when TableKind = 'V' then 'view'
         else TableKind
      end as table_type
    from DBC.TablesV
    where DatabaseName = '{{ schema_relation.schema }}'
      and TableKind in ('T', 'V')

  {% endcall %}
  {{ return(load_result('list_relations_without_caching').table) }}
{% endmacro %}

{% macro teradata__generate_database_name(custom_database_name=none, node=none) -%}
  {% do return(None) %}
{%- endmacro %}
