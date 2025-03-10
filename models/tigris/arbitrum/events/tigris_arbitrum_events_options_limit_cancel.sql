{{ config(
    
    schema = 'tigris_arbitrum',
    alias = 'options_limit_cancel',
    partition_by = ['block_month'],
    materialized = 'incremental',
    file_format = 'delta',
    incremental_strategy = 'merge',
    unique_key = ['evt_block_time', 'evt_tx_hash', 'position_id', 'positions_contract']
    )
}}

WITH 

{% set limit_cancel_tables = [
    'options_evt_OptionsLimitCancelled',
    'Options_V2_evt_OptionsLimitCancelled'
] %}

limit_cancel_v2 AS (
    {% for limit_cancel in limit_cancel_tables %}
        SELECT
            '{{ 'v2.' + loop.index | string }}' as version,
            '2' as protocol_version,
            CAST(date_trunc('DAY', t.evt_block_time) AS date) as day, 
            CAST(date_trunc('MONTH', t.evt_block_time) AS date) as block_month, 
            t.evt_block_time,
            t.evt_tx_hash,
            t.evt_index,
            t.id, 
            contract_address as project_contract_address
        FROM {{ source('tigristrade_v2_arbitrum', limit_cancel) }} t
        {% if is_incremental() %}
        WHERE t.evt_block_time >= date_trunc('day', now() - interval '7' day)
        {% endif %}
        {% if not loop.last %}
        UNION ALL
        {% endif %}
    {% endfor %}
),

get_positions_contract as (
    SELECT 
        a.*,
        c.positions_contract 
    FROM 
    limit_cancel_v2 a 
    INNER JOIN 
    {{ ref('tigris_arbitrum_events_contracts_positions') }} c 
        ON a.project_contract_address = c.trading_contract
        AND a.version = c.trading_contract_version
)

    SELECT 
        l.version,
        l.protocol_version,
        l.day, 
        l.block_month,
        l.evt_block_time,
        l.evt_tx_hash,
        l.evt_index,
        l.id as position_id,
        o.open_price,
        CAST(NULL as double) as close_price,
        CAST(NULL as double) as profitnLoss, 
        o.collateral,
        o.collateral_asset,
        o.direction, 
        o.pair, 
        o.options_period,
        o.referral,
        o.trader,
        o.order_type,
        l.positions_contract,
        l.project_contract_address
    FROM 
    get_positions_contract l 
    INNER JOIN 
    {{ ref('tigris_arbitrum_events_options_open_position') }} o 
        ON l.id = o.position_id