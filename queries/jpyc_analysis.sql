-- ============================================================================
-- 新JPYC 総合分析クエリ
-- ============================================================================
-- 作成日: 2026-01-25
-- 対象: 新JPYC（2025年10月27日ローンチ）
-- チェーン: Ethereum, Polygon, Avalanche
-- コントラクトアドレス: 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
--
-- このクエリは以下を計算します:
-- - 累積取引量（円建て）
-- - 累積取引数
-- - 累積ユーザー数（チェーン別）
-- - 累積ユニークユーザー数（全チェーン統合、重複除外）
-- ============================================================================

WITH all_transfers AS (
    -- Ethereum
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Ethereum' as chain,
        value / 1e18 as amount_jpy,
        "from" as from_address,
        "to" as to_address
    FROM erc20_ethereum.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
    AND evt_block_time >= TIMESTAMP '2025-10-27'  -- JPYCローンチ日以降
    
    UNION ALL
    
    -- Polygon
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Polygon' as chain,
        value / 1e18 as amount_jpy,
        "from" as from_address,
        "to" as to_address
    FROM erc20_polygon.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
    AND evt_block_time >= TIMESTAMP '2025-10-27'  -- JPYCローンチ日以降
    
    UNION ALL
    
    -- Avalanche
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Avalanche' as chain,
        value / 1e18 as amount_jpy,
        "from" as from_address,
        "to" as to_address
    FROM erc20_avalanche_c.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
    AND evt_block_time >= TIMESTAMP '2025-10-27'  -- JPYCローンチ日以降
),

-- 日次統計（チェーン別）
daily_stats_by_chain AS (
    SELECT 
        day,
        chain,
        COUNT(*) as daily_tx_count,
        SUM(amount_jpy) as daily_volume_jpy
    FROM all_transfers
    GROUP BY day, chain
),

-- チェーン別のユニークユーザー計算
all_addresses_by_chain AS (
    SELECT day, chain, from_address as address FROM all_transfers
    UNION ALL
    SELECT day, chain, to_address as address FROM all_transfers
),

first_appearance_by_chain AS (
    SELECT 
        chain,
        address,
        MIN(day) as first_day
    FROM all_addresses_by_chain
    GROUP BY chain, address
),

daily_new_users_by_chain AS (
    SELECT 
        first_day as day,
        chain,
        COUNT(*) as new_users
    FROM first_appearance_by_chain
    GROUP BY first_day, chain
),

-- グローバル（全チェーン統合）のユニークユーザー計算
all_addresses_global AS (
    SELECT day, from_address as address FROM all_transfers
    UNION ALL
    SELECT day, to_address as address FROM all_transfers
),

first_appearance_global AS (
    SELECT 
        address,
        MIN(day) as first_day
    FROM all_addresses_global
    GROUP BY address
),

daily_new_users_global AS (
    SELECT 
        first_day as day,
        COUNT(*) as new_users_global
    FROM first_appearance_global
    GROUP BY first_day
),

-- データ結合
combined AS (
    SELECT 
        COALESCE(s.day, u.day) as day,
        COALESCE(s.chain, u.chain) as chain,
        COALESCE(s.daily_tx_count, 0) as daily_transactions,
        COALESCE(s.daily_volume_jpy, 0) as daily_volume_jpy,
        COALESCE(u.new_users, 0) as daily_new_users_by_chain
    FROM daily_stats_by_chain s
    FULL OUTER JOIN daily_new_users_by_chain u 
        ON s.day = u.day AND s.chain = u.chain
),

-- グローバル値を先に計算（ウィンドウ関数のネスト回避）
with_global_daily AS (
    SELECT 
        c.day,
        c.chain,
        c.daily_transactions,
        c.daily_volume_jpy,
        c.daily_new_users_by_chain,
        -- グローバル新規ユーザー数（重複排除）
        -- 各日の最初のチェーン（アルファベット順）の行にだけ値を設定
        CASE 
            WHEN c.chain = FIRST_VALUE(c.chain) OVER (PARTITION BY c.day ORDER BY c.chain) 
            THEN COALESCE(g.new_users_global, 0) 
            ELSE 0 
        END as daily_new_users_global
    FROM combined c
    LEFT JOIN daily_new_users_global g ON c.day = g.day
)

-- 最終出力：累積値を計算
SELECT 
    day,
    chain,
    
    -- 日次データ
    daily_transactions,
    daily_volume_jpy,
    daily_new_users_by_chain,
    daily_new_users_global,
    
    -- 累積データ（チェーン別）
    SUM(daily_transactions) OVER (PARTITION BY chain ORDER BY day) as cumulative_transactions,
    SUM(daily_volume_jpy) OVER (PARTITION BY chain ORDER BY day) as cumulative_volume_jpy,
    SUM(daily_new_users_by_chain) OVER (PARTITION BY chain ORDER BY day) as cumulative_users_by_chain,
    
    -- 累積グローバルユーザー数（重複排除）
    SUM(daily_new_users_global) OVER (ORDER BY day) as cumulative_users_global
    
FROM with_global_daily
WHERE day >= DATE '2025-10-01'  -- 表示期間（累積値は全期間で計算）
ORDER BY day, chain
