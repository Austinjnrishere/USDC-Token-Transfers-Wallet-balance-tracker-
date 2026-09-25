{{ config(
    materialized='incremental',
    on_schema_change='append_new_columns'
) }}

WITH transfers AS (
    SELECT * FROM {{ ref('usdc_transfers') }}

    {% if is_incremental() %}
      -- Only read transfers that arrived since the last dbt run
      WHERE ingested_at > (SELECT MAX(ingested_at) FROM {{ this }})
    {% endif %}
),

outflows AS (
    SELECT
        from_address AS wallet_address,
        block_number,
        block_timestamp,
        partition_date,
        -1 * (TRY_TO_NUMBER(raw_value, 38, 0) / 1000000.0) AS usdc_delta,
        ingested_at
    FROM transfers
    WHERE from_address != '0x0000000000000000000000000000000000000000'
),

inflows AS (
    SELECT
        to_address AS wallet_address,
        block_number,
        block_timestamp,
        partition_date,
        (TRY_TO_NUMBER(raw_value, 38, 0) / 1000000.0) AS usdc_delta,
        ingested_at
    FROM transfers
    WHERE to_address != '0x0000000000000000000000000000000000000000'
)

SELECT * FROM outflows
UNION ALL
SELECT * FROM inflows