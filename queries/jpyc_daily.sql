-- ============================================================================
-- 新JPYC 発行・償還・流通額 日次推移分析クエリ（単位：億円）v2
-- ============================================================================
-- 対象: 新JPYC（2025年10月27日ローンチ）
-- チェーン: Ethereum, Polygon, Avalanche
-- JPYC社ウォレット: Mintイベントの受け取りアドレス（時期制限なし・動的判定）
-- 発行 = JPYC社ウォレットからの送信
-- 償還 = JPYC社ウォレットへの受信
-- 全チェーン×全日を表示（累積値の歯抜け防止）
-- ============================================================================

WITH jpyc_wallets AS (
    -- Ethereum - Mintの受け取りアドレス（時期制限なし）
    SELECT DISTINCT "to" as wallet_address, 'Ethereum' as chain
    FROM erc20_ethereum.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" = 0x0000000000000000000000000000000000000000
    
    UNION ALL
    
    -- Polygon - Mintの受け取りアドレス（時期制限なし）
    SELECT DISTINCT "to" as wallet_address, 'Polygon' as chain
    FROM erc20_polygon.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" = 0x0000000000000000000000000000000000000000
    
    UNION ALL
    
    -- Avalanche - Mintの受け取りアドレス（時期制限なし）
    SELECT DISTINCT "to" as wallet_address, 'Avalanche' as chain
    FROM erc20_avalanche_c.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" = 0x0000000000000000000000000000000000000000
),

all_transfers AS (
    -- Ethereum - 全てのTransfer（10月27日以降のみ）
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Ethereum' as chain,
        "from" as from_address,
        "to" as to_address,
        value / 1e18 as amount_jpy
    FROM erc20_ethereum.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND evt_block_time >= TIMESTAMP '2025-10-27'
    
    UNION ALL
    
    -- Polygon - 全てのTransfer（10月27日以降のみ）
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Polygon' as chain,
        "from" as from_address,
        "to" as to_address,
        value / 1e18 as amount_jpy
    FROM erc20_polygon.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND evt_block_time >= TIMESTAMP '2025-10-27'
    
    UNION ALL
    
    -- Avalanche - 全てのTransfer（10月27日以降のみ）
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Avalanche' as chain,
        "from" as from_address,
        "to" as to_address,
        value / 1e18 as amount_jpy
    FROM erc20_avalanche_c.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND evt_block_time >= TIMESTAMP '2025-10-27'
),

-- 存在する日の範囲を取得
date_range AS (
    SELECT 
        CAST(MIN(day) as DATE) as min_day,
        CAST(MAX(day) as DATE) as max_day
    FROM all_transfers
),

-- 全日付を生成
all_days AS (
    SELECT 
        CAST(d.day as TIMESTAMP) as day
    FROM date_range dr
    CROSS JOIN UNNEST(SEQUENCE(dr.min_day, dr.max_day, INTERVAL '1' day)) AS d(day)
),

-- 全チェーンのリスト
all_chains AS (
    SELECT 'Ethereum' as chain
    UNION ALL SELECT 'Polygon'
    UNION ALL SELECT 'Avalanche'
),

-- 全日×全チェーンの組み合わせ
all_day_chains AS (
    SELECT d.day, c.chain
    FROM all_days d
    CROSS JOIN all_chains c
),

-- JPYC社ウォレットとのやり取りを判定
jpyc_issuance_and_redemption AS (
    SELECT 
        t.day,
        t.chain,
        CASE 
            WHEN EXISTS (SELECT 1 FROM jpyc_wallets w WHERE w.wallet_address = t.from_address AND w.chain = t.chain) THEN 'issuance'
            WHEN EXISTS (SELECT 1 FROM jpyc_wallets w WHERE w.wallet_address = t.to_address AND w.chain = t.chain) THEN 'redemption'
            ELSE 'transfer'
        END as type,
        t.amount_jpy,
        t.from_address,
        t.to_address
    FROM all_transfers t
),

-- 日次・チェーン別の発行額と償還額
daily_stats_by_chain AS (
    SELECT 
        day,
        chain,
        SUM(CASE WHEN type = 'issuance' THEN amount_jpy ELSE 0 END) as daily_issuance,
        SUM(CASE WHEN type = 'redemption' THEN amount_jpy ELSE 0 END) as daily_redemption
    FROM jpyc_issuance_and_redemption
    GROUP BY 1, 2
),

-- 全日×全チェーンにデータを結合（データがない日は0）
complete_daily_stats AS (
    SELECT 
        adc.day,
        adc.chain,
        COALESCE(ds.daily_issuance, 0) as daily_issuance,
        COALESCE(ds.daily_redemption, 0) as daily_redemption
    FROM all_day_chains adc
    LEFT JOIN daily_stats_by_chain ds 
        ON adc.day = ds.day AND adc.chain = ds.chain
),

-- ユニークユーザー計算（通常のTransferのみ）
normal_transfers AS (
    SELECT day, chain, from_address, to_address
    FROM jpyc_issuance_and_redemption
    WHERE type = 'transfer'
),

all_addresses_by_chain AS (
    SELECT day, chain, from_address as address FROM normal_transfers
    UNION ALL
    SELECT day, chain, to_address as address FROM normal_transfers
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

-- ユニークユーザー計算（グローバル）
all_addresses_global AS (
    SELECT day, from_address as address FROM normal_transfers
    UNION ALL
    SELECT day, to_address as address FROM normal_transfers
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
with_users AS (
    SELECT 
        c.day,
        c.chain,
        c.daily_issuance,
        c.daily_redemption,
        COALESCE(u.new_users, 0) as daily_new_users_by_chain
    FROM complete_daily_stats c
    LEFT JOIN daily_new_users_by_chain u 
        ON c.day = u.day AND c.chain = u.chain
),

with_global_daily AS (
    SELECT 
        w.day,
        w.chain,
        w.daily_issuance,
        w.daily_redemption,
        w.daily_new_users_by_chain,
        CASE 
            WHEN w.chain = 'Avalanche'
            THEN COALESCE(g.new_users_global, 0) 
            ELSE 0 
        END as daily_new_users_global
    FROM with_users w
    LEFT JOIN daily_new_users_global g ON w.day = g.day
),

-- 活動がある日のフラグ（発行・償還・通常Transferのいずれかがある）
activity_flag AS (
    SELECT DISTINCT day, chain
    FROM jpyc_issuance_and_redemption
)

-- 最終出力（活動がある日のみ表示）
SELECT 
    format_datetime(w.day, 'yyyy-MM-dd') as "日付",
    w.chain as "チェーン",
    
    -- 日次発行額（億円）
    ROUND(w.daily_issuance / 1e8, 4) as "日次発行額 (億円)",
    
    -- 日次償還額（億円）
    ROUND(w.daily_redemption / 1e8, 4) as "日次償還額 (億円)",
    
    -- 日次純増額（億円）= 発行 - 償還
    ROUND((w.daily_issuance - w.daily_redemption) / 1e8, 4) as "日次純増額 (億円)",
    
    -- 累積発行額（億円）
    ROUND(SUM(w.daily_issuance) OVER (PARTITION BY w.chain ORDER BY w.day) / 1e8, 2) as "累積発行額 (億円)",
    
    -- 累積償還額（億円）
    ROUND(SUM(w.daily_redemption) OVER (PARTITION BY w.chain ORDER BY w.day) / 1e8, 2) as "累積償還額 (億円)",
    
    -- 累積流通額（億円）= 累積発行 - 累積償還
    ROUND((SUM(w.daily_issuance) OVER (PARTITION BY w.chain ORDER BY w.day) - 
           SUM(w.daily_redemption) OVER (PARTITION BY w.chain ORDER BY w.day)) / 1e8, 2) as "累積流通額 (億円)",
    
    -- 日次新規ユーザー（チェーン別）
    w.daily_new_users_by_chain as "日次新規ユーザー (チェーン別)",
    
    -- 累積ユーザー数（チェーン別）
    SUM(w.daily_new_users_by_chain) OVER (PARTITION BY w.chain ORDER BY w.day) as "累積ユーザー数 (チェーン別)",
    
    -- 総累積ユニークユーザー数
    SUM(w.daily_new_users_global) OVER (ORDER BY w.day) as "総累積ユニークユーザー数"
    
FROM with_global_daily w
INNER JOIN activity_flag af ON w.day = af.day AND w.chain = af.chain
WHERE w.day >= DATE '2025-10-27'
ORDER BY w.day DESC, w.chain ASC
