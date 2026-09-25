{{ config(
    materialized='incremental',
    unique_key='wallet_daily_id',
    incremental_strategy='delete+insert',
    cluster_by=['date_day']
) }}

WITH deltas AS (
    SELECT * FROM {{ ref('usdc_wallet_deltas') }}

    {% if is_incremental() %}
      -- Recalculate balances only for dates that received new deltas in this run
      WHERE partition_date >= (
          SELECT MIN(partition_date) 
          FROM {{ ref('usdc_wallet_deltas') }} 
          WHERE ingested_at > (SELECT MAX(ingested_at) FROM {{ this }})
      )
    {% endif %}
),

daily_net_changes AS (
    SELECT
        wallet_address,
        partition_date AS date_day,
        SUM(usdc_delta) AS net_daily_change
    FROM deltas
    GROUP BY 1, 2
),

cumulative_balances AS (
    SELECT
        wallet_address,
        date_day,
        net_daily_change,
        SUM(net_daily_change) OVER (
            PARTITION BY wallet_address 
            ORDER BY date_day 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS end_of_day_usdc_balance
    FROM daily_net_changes
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['wallet_address', 'date_day']) }} AS wallet_daily_id,
    wallet_address,
    date_day,
    net_daily_change,
    ROUND(end_of_day_usdc_balance, 2) AS usdc_balance,
    CURRENT_TIMESTAMP() AS ingested_at
FROM cumulative_balances