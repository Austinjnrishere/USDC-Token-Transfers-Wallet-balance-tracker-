# 🪙 USDC Token Transfer & Wallet Balance Tracker (dbt + Snowflake)

An automated, production-grade Web3 data pipeline built on Snowflake and dbt to process raw Ethereum USDC token transfer logs, model double-entry ledger flows, and track daily cumulative wallet balances with continuous GitHub Actions CI/CD testing.

---

## 📌 Project Overview

EVM token logs record transfers as raw event payloads containing sender (`from_address`), receiver (`to_address`), and 256-bit unsigned integer values ($10^6$ decimals for USDC).

This project cleans landed JSON logs in Snowflake and uses dbt to transform single transaction events into a **double-entry ledger**, building an incremental analytics mart that tracks the daily cumulative end-of-day USDC balance for every wallet.

---

## 🏗️ Data Architecture & Pipeline Lineage

![dbt Project Architecture](assets/pipelinediagram.drawio.png)


---

## 📂 Model Breakdown & Design Rationale

| Layer | Model Name | Materialization | Purpose & Rationale |
| :--- | :--- | :--- | :--- |
| **Staging** | `stg_usdc_transfers` | `view` | **Filters & Cleans:** Selects USDC transfers (`0xa0b8...eb48`), formats EVM hex addresses to lowercase 20-byte strings, preserves `raw_value` as a string to prevent precision loss, and generates surrogate primary keys (`tx_hash` + `log_index`). |
| **Intermediate** | `int_usdc_wallet_deltas` | `incremental` | **Unpivots Ledger:** A single transfer log contains both sender and receiver. This model unpivots each transaction into two entries (a **negative delta** for sender outflow and a **positive delta** for recipient inflow) and divides raw values by $10^6$ to compute exact human-readable USDC dollar amounts. |
| **Marts** | `fct_daily_usdc_wallet_balances` | `incremental` | **Balance Aggregator:** Sums net daily changes per wallet and uses a window function (`SUM() OVER`) to compute cumulative running balances per wallet over time. |

---

## 🔄 Automated Ingestion & Incremental Logic

1. **Snowflake Ingestion:** Landed JSON files are automatically parsed and copied into Snowflake via automated `TASK` and `COPY INTO` background routines.
2. **Incremental Processing:** 
   - `usdc_transfers` and `usdc_wallet_deltas` use append-only incremental processing based on `ingested_at` timestamps.
   - `daily_usdc_wallet_balances` uses dynamic partition overwrite (`delete+insert`) to recalculate running totals exclusively for dates affected by newly arrived transactions.

---

## 🛡️ Data Quality & Automated CI/CD

### 1. Data Quality Testing (`schema.yml`)
- **Uniqueness & Non-Null Checks:** Ensures primary surrogate keys (`tx_hash_log_index`, `wallet_daily_id`) stay unique across incremental builds.
- **Grain Integrity:** Uses `dbt_utils.unique_combination_of_columns` to enforce exactly one daily balance snapshot per wallet per calendar date.

### 2. GitHub Actions CI/CD Pipeline (`.github/workflows/dbt_ci.yml`)
Every Pull Request to `main` triggers an automated GitHub Actions pipeline that:
- Connects securely to Snowflake using RSA Private Key authentication.
- Installs project packages (`dbt-utils`).
- Executes `dbt debug`, `dbt run`, and `dbt test` to guarantee model compilation and data quality pass before merging code.

```yaml
name: dbt CI

on:
  pull_request:
    branches:
      - main

jobs:
  dbt-ci:
    runs-on: ubuntu-latest
    environment: DBT_USDC

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install dbt-core==1.9.4 dbt-snowflake==1.9.4

      - name: Set up dbt profile and private key
        run: |
          mkdir -p ~/.dbt
          echo "$USDC_PROFILES" > ~/.dbt/profiles.yml
          echo "$USDC_PRIVATE_KEY" > ~/.dbt/rsa_key
          chmod 600 ~/.dbt/rsa_key
        env:
          USDC_PROFILES: ${{ secrets.USDC_PROFILES }}
          USDC_PRIVATE_KEY: ${{ secrets.USDC_PRIVATE_KEY }}

      - name: Install dbt packages
        run: dbt deps

      - name: Test Snowflake Connection
        run: dbt debug

      - name: Run dbt Models
        run: dbt run --target ci

      - name: Test dbt Models
        run: dbt test --target ci


🚀 Quickstart Guide

# Clone the repository
git clone [https://github.com/your-username/USDC-Token-Transfers-Wallet-balance-tracker.git](https://github.com/your-username/USDC-Token-Transfers-Wallet-balance-tracker.git)
cd USDC-Token-Transfers-Wallet-balance-tracker

# Create and activate Python virtual environment
python -m venv usdcvenv
usdcvenv\Scripts\activate  # On Linux/macOS: source usdcvenv/bin/activate

# Install required packages
pip install dbt-core dbt-snowflake
dbt deps
