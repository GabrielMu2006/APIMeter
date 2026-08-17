# DeepSeek Usage Export - CSV Schema

> Documented from REAL exports (2026-07-19 to 2026-08-17, exported from
> platform.deepseek.com). Never guessed - every field below was observed in
> actual files and verified by the analyzer.

## File structure

The official export produces TWO CSV files per date range (or one ZIP
containing both):

- `amount-<from>_<to>.csv` - token and request QUANTITIES, per API key
- `cost-<from>_<to>.csv` - monetary COST, per model (no key dimension)

Both files are UTF-8 with BOM.

## amount file (quantities)

Header (exact, verified):

```
user_id,start_time_iso,end_time_iso,model,api_key_name,api_key,type,price,amount
```

| Column | Meaning | Observed values |
|--------|---------|-----------------|
| user_id | account identifier | e.g. Wechat-<uuid> |
| start_time_iso | bucket start, ISO8601 with offset | 2026-07-22T00:00:00+08:00 |
| end_time_iso | bucket end (EXCLUSIVE) | 2026-07-23T00:00:00+08:00 |
| model | model name | deepseek-v4-pro, deepseek-v4-flash |
| api_key_name | official local key name | deerflow, Codex, ... |
| api_key | MASKED key (DeepSeek masks it) | sk-92063***********************e267 |
| type | row kind (long format) | input_cache_hit_tokens / input_cache_miss_tokens / output_tokens / request_count |
| price | per-unit price (empty for request_count) | 0.000000025 |
| amount | quantity of the type | 11464960 (tokens) / 145 (requests) |

The file is LONG format: one row per (day, model, key, type).

## cost file (money)

Header (exact, verified):

```
user_id,start_time_iso,end_time_iso,model,wallet_type,cost,currency
```

| Column | Meaning | Observed values |
|--------|---------|-----------------|
| wallet_type | billing wallet | Paid |
| cost | exact decimal amount | 2.9492980000000000 |
| currency | ISO code | CNY |

One row per (day, model). NO api key columns - the official export does
NOT attribute cost to individual API keys.

## Verification matrix (the facts that matter)

| Question | Answer |
|----------|--------|
| Daily granularity | YES - day buckets at 00:00:00+08:00, end exclusive |
| API key granularity | YES for quantities (name + masked key); NO for cost |
| Request count | YES - type=request_count rows |
| Token data | YES - cache hit / cache miss / output (no total column; total is computed as the sum) |
| Model data | YES |
| Amount / money | YES - cost file, per day+model, CNY |
| Per-key cost | DERIVED: price x amount summed per (day, model, key) from the amount file - cross-checked against the cost file per (day, model); mismatch downgrades to estimated |

## Mapping rules implemented in DeepSeekOfficialCSVMapper

1. amount rows are grouped by (day, model, masked api_key) and summed per
   type into one UsageRecord per group.
2. input_tokens = cache_hit + cache_miss; total_tokens = cache_hit +
   cache_miss + output (arithmetic on provided fields, never guessed).
3. The api key identity is the MASKED key string (that is all DeepSeek
   exports). Its SHA256 is the fingerprint; api_key_name becomes the
   official display name.
4. cost rows become UsageRecords with amount+currency and NO key,
   NO tokens, NO requests (honest unknowns).
5. The day bucket is the date part of start_time_iso in the timestamp's own
   offset (+08:00) - the billing day stays correct regardless of the Mac's
   timezone.
6. price values from the export seed versioned price_rules (per model, per
   day, official data - no hardcoded prices anywhere).
7. Unknown type values or unparseable amounts throw - partial silent
   imports are forbidden (spec 82).

## Consequences for the product

- Historical daily cost: fully supported from official data.
- Per-key cost breakdown: derived from the official amount file
  (price x amount), verified against the cost file at import time. On
  mismatch the derived rows are marked estimated - never fabricated.
- Official CSV always overrides gateway estimates for a day (spec 26).
