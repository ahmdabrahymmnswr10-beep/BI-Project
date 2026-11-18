# Olist Seller Performance | Track E

This team project analyzes seller sales, activity and associated service outcomes using the Brazilian E-Commerce Public Dataset by Olist. The analysis window is purchase timestamp **2017-01-01 inclusive to 2018-09-01 exclusive**; sales questions use delivered orders unless stated otherwise.

## Contents

- `sql/01_schema.sql` — SQL Server staging table definitions.
- `sql/02_validation.sql` — row, key, value and foreign-key checks.
- `sql/03_analysis.sql` — G1-G3, E1-E7 and additional questions O1-O2.
- `sql/04_dashboard_exports.sql` — export guidance for the Excel workbook.
- `dashboard/Track_E_Seller_Performance_Dashboard.xlsx` — interactive workbook with filter controls, SQL-derived result tables, charts and KPI reconciliation.
- `report/Track_E_Findings_Report.pdf` — scenario, findings, recommendations and limitations.
- `docs/` — question answers, prioritized recommendations, data dictionary, ERD, SQL coverage map and contribution template.
- `data/README.md` — source data inventory and import notes; raw CSV files are not included in this GitHub-ready folder.
- `results/` — compact CSV evidence by question ID. `tools/build_results.py` reproduces these exports from the original CSV files.

## Source data and attribution

Download the eight CSV files listed in the project brief from [Olist on Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce). Keep the raw files outside GitHub. This project uses customers, orders, order items, sellers, products, payments, reviews, and category translation. Geolocation data is not required. Dataset license listed by Olist: CC BY-NC-SA 4.0; check the source page before public redistribution.

## Run order in SQL Server

1. Create an empty project database and run `sql/01_schema.sql`.
2. Import the eight CSVs as UTF-8 with headers into the matching `dbo` tables. Preserve IDs and postal prefixes as text, monetary columns as decimal, timestamps as `datetime2`, and blank dates as `NULL`. Record the exact Import Flat File settings used.
3. Run `sql/02_validation.sql`. Resolve import or key problems before analysis; expected multiple reviews per order are retained for audit.
4. Run the labelled query blocks in `sql/03_analysis.sql`; save each output with its query ID in `results/`.
5. Run `sql/04_dashboard_exports.sql` guidance, import the result tables into the workbook, and reconcile unfiltered KPI cards.

The SQL scripts target SQL Server 2019+ T-SQL. No local SQL Server instance was reachable while this package was assembled, so the query files are prepared for execution but were not executed against a SQL Server engine here. The supplied CSV result tables were calculated from the same source files using the included Python/pandas builder and the documented grains/definitions. Run the SQL in your course environment and reconcile before final upload.

Rebuild the CSV result exports with the bundled Python runtime or a local Python environment with pandas and NumPy:

```powershell
python tools/build_results.py --data-dir "PATH_TO_OLIST_CSV_FOLDER" --out-dir "results"
```

## Metric and grain rules

- Merchandise sales are `SUM(order_items.price)` in BRL; freight is excluded and sales are not profit or commission revenue.
- Seller totals are attributed at item grain. A shared order can count for several sellers; seller order and service counts therefore overlap and must not be summed into marketplace totals.
- One valid review (score 1–5) per order is selected by latest non-null answer timestamp, then creation date, review ID and source-row order. Scores 1–2 are low ratings.
- Late means actual delivery calendar date is after estimated delivery calendar date. Orders missing either date are outside the late-rate denominator.
- Keep numerators and denominators from the result tables. Recalculate rates from sums after filtering; do not average percentages or averages.

## Software and team information

Database target: SQL Server T-SQL (record the exact server version used by the team). Workbook target: Excel `.xlsx`, Excel 2016 or later. Team members: محمد وائل مجدي حسن سلطان؛ حسن محمد حسن عامر؛ السيد حسين حماد؛ أحمد إبراهيم علي منصور. Add the actual SQL Server/Excel versions and each member’s factual contribution before final submission.

## Headline evidence

- 96,211 delivered orders from 99,092 scoped orders.
- Merchandise sales: R$ 13,181,027.13; delivered-order AOV: R$ 137.00.
- 2,945 sellers have delivered item sales; 625 meet E7's 30-order threshold.

## Repository structure suggestion

Keep raw CSV files out of the repository. Include scripts, aggregate CSV evidence, workbook, report, ERD, dictionary, coverage map and a dashboard screenshot. Do not commit credentials or local absolute file paths.



