{{ config(
        schema = 'balancer',
        alias = 'liquidity', 
        
        post_hook='{{ expose_spells(\'["ethereum","arbitrum", "optimism", "polygon", "gnosis","avalanche_c", "base" 
        ]\',
                                "project",
                                "balancer",
                                \'["viniabussafi"]\') }}'
        )
}}

{% set balancer_models = [
ref('balancer_v2_ethereum_liquidity')
, ref('balancer_v2_optimism_liquidity')
, ref('balancer_v2_arbitrum_liquidity')
, ref('balancer_v2_polygon_liquidity')
, ref('balancer_v2_gnosis_liquidity')
, ref('balancer_v2_avalanche_c_liquidity')
, ref('balancer_v2_base_liquidity')
] %}


SELECT *
FROM (
    {% for liquidity_model in balancer_models %}
    SELECT
    day,
    pool_id,
    pool_symbol,
    blockchain,
    token_address,
    token_symbol,
    token_balance_raw,
    token_balance,
    protocol_liquidity_usd,
    pool_liquidity_usd
    FROM {{ liquidity_model }}
    {% if not loop.last %}
    UNION ALL
    {% endif %}
    {% endfor %}
)
;