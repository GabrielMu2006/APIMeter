# DeepSeek Usage Export - CSV Schema

> **STATUS: PENDING - awaiting a real usage export file.**
>
> Per the project rules (PROJECT_SPEC.md section 14/117), the DeepSeek CSV
> schema is NEVER guessed. This document will be filled from the analysis of
> a real file exported from the official Usage page.

## How to obtain the export

1. Open https://platform.deepseek.com/usage in your browser.
2. Sign in to your DeepSeek account.
3. Select a month with usage data.
4. Click Export (the official export button on the Usage page).
5. Save the resulting ZIP (or CSV) file.
6. Put the file into the project directory `/Users/gabrielmu/Documents/API Meter/`
   (or tell the agent the full path).

## What happens once the file is provided

1. `apimeter analyze <file>` inspects it and produces the analysis below.
2. The analysis is pasted into this document as the actual schema.
3. A DeepSeek-official CSV mapper is implemented from the FACTS in this
   document - nothing else.
4. The mapper is registered in the CLI and the import pipeline is validated
   end-to-end with the real file.

## Analysis template

```
# DeepSeek Usage Export - Schema Analysis
- Source file: (TBD - real file name)
- Data rows: (TBD)
- Detected granularity: (TBD - daily / perRow / singleDate / ...)
- Date column: (TBD)
- API key column: (TBD)
- Request count column: (TBD)
- Token columns: (TBD)
- Amount column: (TBD)
- Currency column: (TBD)
- Model column: (TBD)
```

## Questions this document must answer (from the real file)

- Does the export have daily granularity? (Risk 2 of PROJECT_SPEC.md)
- Does it identify the API key per row?
- Does it provide request counts?
- Does it provide token data (input/output/cache)?
- Does it provide the model name?
- Does it provide amounts and currency?

Until these are answered from a REAL file, the CSV import mapper is
intentionally not registered (the CLI refuses imports with a clear message).
