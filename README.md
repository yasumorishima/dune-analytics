# Dune Analytics - Blockchain Data Analysis

On-chain data analysis using [Dune Analytics](https://dune.com). This repository contains SQL queries and analysis documentation for blockchain projects.

## Dashboards

### JPYC Stablecoin Analysis

Analysis of **JPYC** - Japan's first regulated stablecoin launched on October 27, 2025.

**[View Dashboard on Dune](https://dune.com/shogaku_toushi/jpyc-date)**

![JPYC Dashboard](images/jpyc-dashboard.png)

#### Key Metrics (as of January 2026)

| Metric | Value |
|--------|-------|
| Cumulative Transactions | ~400,000 |
| Cumulative Volume | ~10 billion JPY |
| Unique Users (deduplicated) | ~100,000 addresses |
| Chains | Ethereum, Polygon, Avalanche |

#### Technical Highlights

- **9 CTEs** for step-by-step data transformation
- **Multi-chain analysis** across Ethereum, Polygon, and Avalanche
- **Window functions** (`SUM OVER`, `FIRST_VALUE`) for cumulative calculations
- **Cross-chain user deduplication** - same address on multiple chains counted once
- **Mint/Burn exclusion** - filters out token issuance/redemption events

#### Files

| File | Description |
|------|-------------|
| [queries/jpyc_analysis.sql](queries/jpyc_analysis.sql) | Main SQL query |
| [docs/jpyc_analysis_blog.md](docs/jpyc_analysis_blog.md) | Detailed explanation (Japanese) |

---

## About

This repository showcases blockchain data analysis skills using SQL on Dune Analytics.

**Tools Used:**
- Dune Analytics (SQL, DuneSQL/Trino)
- On-chain data from Ethereum, Polygon, Avalanche

---

*Powered by [Dune Analytics](https://dune.com)*
