{{ config(
    schema = 'staking_ethereum',
    alias = 'entities_binance',
    
    materialized = 'incremental',
    file_format = 'delta',
    incremental_strategy = 'merge',
    unique_key = ['depositor_address'])
}}

SELECT binance.address AS depositor_address
, 'Binance' AS entity
, CONCAT('Binance ', CAST(ROW_NUMBER() OVER (ORDER BY MIN(t.block_time)) AS VARCHAR)) AS entity_unique_name
, 'CEX' AS category
FROM (
    SELECT 0xf17aced3c7a8daa29ebb90db8d1b6efd8c364a18 AS address
    UNION ALL
    SELECT 0x2f47a1c2db4a3b78cda44eade915c3b19107ddcc AS address
    UNION ALL
    SELECT distinct to AS address
    FROM {{ source('ethereum', 'transactions') }}
    WHERE "from"=0xf17aced3c7a8daa29ebb90db8d1b6efd8c364a18
        AND to !=0x00000000219ab540356cbb839cbe05303d7705fa
        {% if not is_incremental() %}
        AND block_time >= DATE '2020-10-14'
        {% endif %}
        {% if is_incremental() %}
        AND block_time >= date_trunc('day', now() - interval '7' day)
        {% endif %}
    GROUP BY to
) binance
INNER JOIN {{ source('ethereum', 'traces') }} t
    ON binance.address=t."from"
    AND t.to=0x00000000219ab540356cbb839cbe05303d7705fa
    {% if not is_incremental() %}
    AND t.block_time >= DATE '2020-10-14'
    {% endif %}
    {% if is_incremental() %}
    AND t.block_time >= date_trunc('day', now() - interval '7' day)
    {% endif %}
GROUP BY binance.address