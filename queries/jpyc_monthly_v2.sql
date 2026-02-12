-- ============================================================================
-- 新JPYC 発行・償還・流通額 月次累積分析クエリ（単位：億円）v2.1
-- ============================================================================
-- 対象: 新JPYC（2025年10月27日ローンチ）
-- チェーン: Ethereum, Polygon, Avalanche
-- JPYC社ウォレット: Mintイベントの受け取りアドレス（時期制限なし・動的判定）
-- 発行 = JPYC社ウォレットからの送信（10月27日以降）
-- 償還 = JPYC社ウォレットへの受信（10月27日以降）
-- ============================================================================
-- v2.1 変更点:
--   - Mint/Burnイベント除外（0x0アドレスのfrom/toを除外）
--   - JPYC社ウォレット間の内部転送を'internal'として分類
--   - 活動フィルタを日次版と統一（全タイプの活動がある月を表示）
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
    -- Ethereum - 全てのTransfer（10月27日以降、Mint/Burn除外）
    SELECT
        DATE_TRUNC('month', evt_block_time) as month,
        'Ethereum' as chain,
        "from" as from_address,
        "to" as to_address,
        value / 1e18 as amount_jpy
    FROM erc20_ethereum.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND evt_block_time >= TIMESTAMP '2025-10-27'
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000

    UNION ALL

    -- Polygon - 全てのTransfer（10月27日以降、Mint/Burn除外）
    SELECT
        DATE_TRUNC('month', evt_block_time) as month,
        'Polygon' as chain,
        "from" as from_address,
        "to" as to_address,
        value / 1e18 as amount_jpy
    FROM erc20_polygon.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND evt_block_time >= TIMESTAMP '2025-10-27'
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000

    UNION ALL

    -- Avalanche - 全てのTransfer（10月27日以降、Mint/Burn除外）
    SELECT
        DATE_TRUNC('month', evt_block_time) as month,
        'Avalanche' as chain,
        "from" as from_address,
        "to" as to_address,
        value / 1e18 as amount_jpy
    FROM erc20_avalanche_c.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND evt_block_time >= TIMESTAMP '2025-10-27'
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
),

-- JPYC社ウォレットとのやり取りを判定（内部転送を分離）
jpyc_issuance_and_redemption AS (
    SELECT
        t.month,
        t.chain,
        CASE
            WHEN EXISTS (SELECT 1 FROM jpyc_wallets w WHERE w.wallet_address = t.from_address AND w.chain = t.chain)
             AND EXISTS (SELECT 1 FROM jpyc_wallets w WHERE w.wallet_address = t.to_address AND w.chain = t.chain)
            THEN 'internal'
            WHEN EXISTS (SELECT 1 FROM jpyc_wallets w WHERE w.wallet_address = t.from_address AND w.chain = t.chain) THEN 'issuance'
            WHEN EXISTS (SELECT 1 FROM jpyc_wallets w WHERE w.wallet_address = t.to_address AND w.chain = t.chain) THEN 'redemption'
            ELSE 'transfer'
        END as type,
        t.amount_jpy
    FROM all_transfers t
),

-- 活動がある月×チェーン（internal以外の全タイプ）
active_month_chains AS (
    SELECT DISTINCT month, chain
    FROM jpyc_issuance_and_redemption
    WHERE type != 'internal'
),

-- 月次・チェーン別の発行額と償還額
monthly_stats_by_chain AS (
    SELECT
        month,
        chain,
        SUM(CASE WHEN type = 'issuance' THEN amount_jpy ELSE 0 END) as monthly_issuance,
        SUM(CASE WHEN type = 'redemption' THEN amount_jpy ELSE 0 END) as monthly_redemption
    FROM jpyc_issuance_and_redemption
    GROUP BY 1, 2
),

-- 活動がある全組み合わせにデータを結合
complete_monthly_stats AS (
    SELECT
        amc.month,
        amc.chain,
        COALESCE(ms.monthly_issuance, 0) as monthly_issuance,
        COALESCE(ms.monthly_redemption, 0) as monthly_redemption
    FROM active_month_chains amc
    LEFT JOIN monthly_stats_by_chain ms
        ON amc.month = ms.month AND amc.chain = ms.chain
),

-- 全チェーン合計の月次統計
monthly_stats_total AS (
    SELECT
        month,
        SUM(monthly_issuance) as total_monthly_issuance,
        SUM(monthly_redemption) as total_monthly_redemption
    FROM complete_monthly_stats
    GROUP BY 1
),

-- 全体累積値を事前計算
global_cumulative AS (
    SELECT
        month,
        SUM(total_monthly_issuance) OVER (ORDER BY month) as cumulative_global_issuance,
        SUM(total_monthly_redemption) OVER (ORDER BY month) as cumulative_global_redemption
    FROM monthly_stats_total
)

-- 最終出力
SELECT
    format_datetime(c.month, 'yyyy-MM') as "年月",
    c.chain as "チェーン",

    -- 月次発行額（億円）
    ROUND(c.monthly_issuance / 1e8, 2) as "月次発行額 (億円)",

    -- 月次償還額（億円）
    ROUND(c.monthly_redemption / 1e8, 2) as "月次償還額 (億円)",

    -- 月次純増額（億円）= 発行 - 償還
    ROUND((c.monthly_issuance - c.monthly_redemption) / 1e8, 2) as "月次純増額 (億円)",

    -- 累積発行額（億円）
    ROUND(SUM(c.monthly_issuance) OVER (PARTITION BY c.chain ORDER BY c.month) / 1e8, 2) as "累積発行額 (億円)",

    -- 累積償還額（億円）
    ROUND(SUM(c.monthly_redemption) OVER (PARTITION BY c.chain ORDER BY c.month) / 1e8, 2) as "累積償還額 (億円)",

    -- 累積流通額（億円）= 累積発行 - 累積償還
    ROUND((SUM(c.monthly_issuance) OVER (PARTITION BY c.chain ORDER BY c.month) -
           SUM(c.monthly_redemption) OVER (PARTITION BY c.chain ORDER BY c.month)) / 1e8, 2) as "累積流通額 (億円)",

    -- 全チェーン合計の累積発行額（最初のチェーンにのみ表示）
    CASE
        WHEN c.chain = 'Avalanche'
        THEN ROUND(gc.cumulative_global_issuance / 1e8, 2)
        ELSE NULL
    END as "全体累積発行額 (億円)",

    -- 全チェーン合計の累積償還額（最初のチェーンにのみ表示）
    CASE
        WHEN c.chain = 'Avalanche'
        THEN ROUND(gc.cumulative_global_redemption / 1e8, 2)
        ELSE NULL
    END as "全体累積償還額 (億円)",

    -- 全チェーン合計の累積流通額（最初のチェーンにのみ表示）
    CASE
        WHEN c.chain = 'Avalanche'
        THEN ROUND((gc.cumulative_global_issuance - gc.cumulative_global_redemption) / 1e8, 2)
        ELSE NULL
    END as "全体累積流通額 (億円)"

FROM complete_monthly_stats c
LEFT JOIN global_cumulative gc ON c.month = gc.month
ORDER BY c.month DESC, c.chain ASC
