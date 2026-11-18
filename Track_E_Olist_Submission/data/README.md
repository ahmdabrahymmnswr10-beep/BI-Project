# Data Source and Import Notes

This project uses the Brazilian E-Commerce Public Dataset by Olist, available from [Olist on Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).

Use the eight CSVs listed in the project brief: customers, orders, order items, payments, reviews, sellers, products and category translation. Geolocation is optional and is not used for the required questions. Keep source IDs and postal prefixes as text; import CSV as UTF-8; keep quoted review text intact; convert blank timestamps to NULL. Record the download date and dataset version if shown.

Raw source CSV files are not included in this GitHub-ready package. The reproducible aggregate evidence is in `../results/`, and the builder in `../tools/build_results.py` reads a local folder containing the original CSVs.

Download and extract the dataset locally, then run:

```powershell
python tools/build_results.py --data-dir "PATH_TO_OLIST_CSV_FOLDER" --out-dir "results"
```

Import the source CSV files into the SQL Server tables defined in `../sql/01_schema.sql` before running the validation and analysis scripts.
