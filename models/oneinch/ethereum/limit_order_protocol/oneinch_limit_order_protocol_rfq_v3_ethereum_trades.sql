{{  config(
    
        schema='oneinch_limit_order_protocol_rfq_v3_ethereum',
        alias = 'trades',
        partition_by = ['block_month'],
        on_schema_change='sync_all_columns',
        file_format ='delta',
        materialized='incremental',
        incremental_strategy='merge',
        unique_key = ['block_date', 'blockchain', 'project', 'version', 'tx_hash', 'evt_index', 'trace_address']
    )
}}

{% set project_start_date = '2022-11-28' %} --for testing, use small subset of data
{% set burn_address = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' %} --according to etherscan label
{% set blockchain = 'ethereum' %}
{% set blockchain_symbol = 'ETH' %}

WITH limit_order_protocol_rfq_v3 AS
(
    SELECT
        call_block_number,
        contract_address,
        "order",
        output_0,
        output_1,
        call_block_time,
        call_tx_hash,
        call_trace_address
    FROM
        {{ source('oneinch_ethereum', 'AggregationRouterV5_call_fillOrderRFQ') }}
    WHERE
        call_success
        {% if is_incremental() %}
        AND call_block_time >= date_trunc('day', now() - interval '7' Day)
        {% else %}
        AND call_block_time >= TIMESTAMP '{{project_start_date}}'
        {% endif %}
            
    UNION ALL
        
    SELECT
        call_block_number,
        contract_address,
        "order",
        output_filledMakingAmount as output_0,
        output_filledTakingAmount as output_1,
        call_block_time,
        call_tx_hash,
        call_trace_address
    FROM
        {{ source('oneinch_ethereum', 'AggregationRouterV5_call_fillOrderRFQTo') }}
    WHERE
        call_success
        {% if is_incremental() %}
        AND call_block_time >= date_trunc('day', now() - interval '7' Day)
        {% else %}
        AND call_block_time >= TIMESTAMP '{{project_start_date}}'
        {% endif %}
            
    UNION ALL
        
    SELECT
        call_block_number,
        contract_address,
        "order",
        output_0,
        output_1,
        call_block_time,
        call_tx_hash,
        call_trace_address
    FROM
        {{ source('oneinch_ethereum', 'AggregationRouterV5_call_fillOrderRFQToWithPermit') }}
    WHERE
        call_success
        {% if is_incremental() %}
        AND call_block_time >= date_trunc('day', now() - interval '7' Day)
        {% else %}
        AND call_block_time >= TIMESTAMP '{{project_start_date}}'
        {% endif %}
)
, oneinch AS
(
    SELECT
        call_block_number as block_number,
        call_block_time as block_time,
        '1inch Limit Order Protocol' AS project,
        'RFQ v3' as version,
        CAST(NULL as VARBINARY) as taker, --will get from base table downstream
        from_hex(json_extract_scalar("order", '$.maker')) AS maker,
        output_1 AS token_bought_amount_raw,
        output_0 AS token_sold_amount_raw,
        CAST(NULL as double) AS amount_usd,
        from_hex(json_extract_scalar("order", '$.takerAsset')) AS token_bought_address,
        from_hex(json_extract_scalar("order", '$.makerAsset')) AS token_sold_address,
        contract_address AS project_contract_address,
        call_tx_hash as tx_hash,
        call_trace_address AS trace_address,
        CAST(-1 as integer) AS evt_index
    FROM
        limit_order_protocol_rfq_v3
)
SELECT
    '{{blockchain}}' AS blockchain
    ,src.project
    ,src.version
    ,CAST(date_trunc('day', src.block_time) as date) AS block_date
    ,CAST(date_trunc('month', src.block_time) as date) AS block_month
    ,src.block_time
    ,src.block_number
    ,token_bought.symbol AS token_bought_symbol
    ,token_sold.symbol AS token_sold_symbol
    ,case
        when lower(token_bought.symbol) > lower(token_sold.symbol) then concat(token_sold.symbol, '-', token_bought.symbol)
        else concat(token_bought.symbol, '-', token_sold.symbol)
    end as token_pair
    ,src.token_bought_amount_raw / power(10, token_bought.decimals) AS token_bought_amount
    ,src.token_sold_amount_raw / power(10, token_sold.decimals) AS token_sold_amount
    ,src.token_bought_amount_raw
    ,src.token_sold_amount_raw
    ,coalesce(
        src.amount_usd
        , (src.token_bought_amount_raw / power(10,
            CASE
                WHEN token_bought_address = {{burn_address}}
                    THEN 18
                ELSE prices_bought.decimals
            END
            )
        )
        *
        (
            CASE
                WHEN token_bought_address = {{burn_address}}
                    THEN prices_eth.price
                ELSE prices_bought.price
            END
        )
        , (src.token_sold_amount_raw / power(10,
            CASE
                WHEN token_sold_address = {{burn_address}}
                    THEN 18
                ELSE prices_sold.decimals
            END
            )
        )
        *
        (
            CASE
                WHEN token_sold_address = {{burn_address}}
                    THEN prices_eth.price
                ELSE prices_sold.price
            END
        )
    ) AS amount_usd
    ,src.token_bought_address
    ,src.token_sold_address
    ,coalesce(src.taker, tx."from") AS taker
    ,src.maker
    ,src.project_contract_address
    ,src.tx_hash
    ,tx."from" AS tx_from
    ,tx.to AS tx_to
    ,src.trace_address
    ,src.evt_index
FROM oneinch as src
INNER JOIN {{ source('ethereum', 'transactions') }} as tx
    ON src.tx_hash = tx.hash
    AND src.block_number = tx.block_number
    {% if is_incremental() %}
    AND tx.block_time >= date_trunc('day', now() - interval '7' Day)
    {% else %}
    AND tx.block_time >= TIMESTAMP '{{project_start_date}}'
    {% endif %}
LEFT JOIN {{ ref('tokens_erc20') }} as token_bought
    ON token_bought.contract_address = src.token_bought_address
    AND token_bought.blockchain = '{{blockchain}}'
LEFT JOIN {{ ref('tokens_erc20') }} as token_sold
    ON token_sold.contract_address = src.token_sold_address
    AND token_sold.blockchain = '{{blockchain}}'
LEFT JOIN {{ source('prices', 'usd') }} as prices_bought
    ON prices_bought.minute = date_trunc('minute', src.block_time)
    AND prices_bought.contract_address = src.token_bought_address
    AND prices_bought.blockchain = '{{blockchain}}'
    {% if is_incremental() %}
    AND prices_bought.minute >= date_trunc('day', now() - interval '7' Day)
    {% else %}
    AND prices_bought.minute >= TIMESTAMP '{{project_start_date}}'
    {% endif %}
LEFT JOIN {{ source('prices', 'usd') }} as prices_sold
    ON prices_sold.minute = date_trunc('minute', src.block_time)
    AND prices_sold.contract_address = src.token_sold_address
    AND prices_sold.blockchain = '{{blockchain}}'
    {% if is_incremental() %}
    AND prices_sold.minute >= date_trunc('day', now() - interval '7' Day)
    {% else %}
    AND prices_sold.minute >= TIMESTAMP '{{project_start_date}}'
    {% endif %}
LEFT JOIN {{ source('prices', 'usd') }} as prices_eth
    ON prices_eth.minute = date_trunc('minute', src.block_time)
    AND prices_eth.blockchain is null
    AND prices_eth.symbol = '{{blockchain_symbol}}'
    {% if is_incremental() %}
    AND prices_eth.minute >= date_trunc('day', now() - interval '7' Day)
    {% else %}
    AND prices_eth.minute >= TIMESTAMP '{{project_start_date}}'
    {% endif %}