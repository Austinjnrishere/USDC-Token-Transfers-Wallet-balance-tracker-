{{ config(
    materialized='incremental',
    unique_key='tx_hash_log_index',
    on_schema_change='append_new_columns'
) }}

WITH source AS (
    SELECT 
        *,
        {{ dbt_utils.generate_surrogate_key(['transaction_hash', 'log_index']) }} AS tx_hash_log_index
    FROM {{ source('usdc_source', 'raw_tx') }}

    {% if is_incremental() %}
      -- Process only newly landed records since the max timestamp in this model
      WHERE ingested_at > (SELECT MAX(ingested_at) FROM {{ this }})
    {% endif %}
)

SELECT
    tx_hash_log_index,
    transaction_hash,
    log_index,
    block_number,
    block_timestamp,
    from_address,
    to_address,
    raw_value,
    partition_date,
    ingested_at
FROM source
WHERE LOWER(token_address) = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48'