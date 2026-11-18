from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd


FILES = {
    "customers": "olist_customers_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "items": "olist_order_items_dataset.csv",
    "payments": "olist_order_payments_dataset.csv",
    "reviews": "olist_order_reviews_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "products": "olist_products_dataset.csv",
    "translation": "product_category_name_translation.csv",
}
START = pd.Timestamp("2017-01-01")
END = pd.Timestamp("2018-09-01")


def load_csv(folder: Path, name: str) -> pd.DataFrame:
    return pd.read_csv(folder / name, encoding="utf-8", low_memory=False)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", required=True)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()
    src = Path(args.data_dir)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    customers = load_csv(src, FILES["customers"])
    orders = load_csv(src, FILES["orders"])
    items = load_csv(src, FILES["items"])
    payments = load_csv(src, FILES["payments"])
    reviews = load_csv(src, FILES["reviews"])
    sellers = load_csv(src, FILES["sellers"])
    products = load_csv(src, FILES["products"])
    translation = load_csv(src, FILES["translation"])

    for c in ["order_purchase_timestamp", "order_delivered_customer_date", "order_estimated_delivery_date"]:
        orders[c] = pd.to_datetime(orders[c], errors="coerce")
    items["price"] = pd.to_numeric(items["price"], errors="coerce")
    items["freight_value"] = pd.to_numeric(items["freight_value"], errors="coerce")
    reviews["review_score"] = pd.to_numeric(reviews["review_score"], errors="coerce")
    reviews["review_answer_timestamp"] = pd.to_datetime(reviews["review_answer_timestamp"], errors="coerce")
    reviews["review_creation_date"] = pd.to_datetime(reviews["review_creation_date"], errors="coerce")
    reviews["_source_row"] = np.arange(len(reviews))

    scoped = orders.loc[
        orders.order_purchase_timestamp.ge(START)
        & orders.order_purchase_timestamp.lt(END)
    ].copy()
    delivered = scoped.loc[scoped.order_status.eq("delivered")].copy()
    delivered["purchase_month"] = delivered.order_purchase_timestamp.dt.to_period("M").astype(str)
    delivered["purchase_date"] = delivered.order_purchase_timestamp.dt.date
    delivered = delivered.merge(customers[["customer_id", "customer_unique_id", "customer_state", "customer_city"]], on="customer_id", how="left", validate="many_to_one")

    # One analysis review per order: latest non-null answer timestamp; creation date,
    # review id and source row break ties. Invalid scores are excluded from the analysis view.
    valid_reviews = reviews.loc[reviews.review_score.between(1, 5)].copy()
    valid_reviews["_answer_sort"] = valid_reviews.review_answer_timestamp.fillna(pd.Timestamp("1900-01-01"))
    valid_reviews["_creation_sort"] = valid_reviews.review_creation_date.fillna(pd.Timestamp("1900-01-01"))
    selected_reviews = (valid_reviews.sort_values(
        ["_answer_sort", "_creation_sort", "review_id", "_source_row"],
        kind="mergesort"
    ).drop_duplicates("order_id", keep="last"))
    review_orders = selected_reviews[["order_id", "review_id", "review_score", "review_creation_date", "review_answer_timestamp"]].copy()

    order_items = items.loc[items.order_id.isin(delivered.order_id)].copy()
    order_items["price"] = order_items.price.fillna(0)
    order_items["freight_value"] = order_items.freight_value.fillna(0)
    item_base = (order_items
        .merge(delivered[["order_id", "purchase_month", "purchase_date", "customer_id", "customer_unique_id", "customer_state", "order_delivered_customer_date", "order_estimated_delivery_date"]], on="order_id", how="inner", validate="many_to_one")
        .merge(sellers[["seller_id", "seller_state", "seller_city"]], on="seller_id", how="left", validate="many_to_one")
        .merge(products[["product_id", "product_category_name"]], on="product_id", how="left", validate="many_to_one")
        .merge(translation, on="product_category_name", how="left", validate="many_to_one"))
    item_base["category"] = item_base.product_category_name_english.fillna(item_base.product_category_name).fillna("Unknown / untranslated")
    item_base["is_late"] = (
        item_base.order_delivered_customer_date.notna()
        & item_base.order_estimated_delivery_date.notna()
        & item_base.order_delivered_customer_date.dt.normalize().gt(item_base.order_estimated_delivery_date.dt.normalize())
    )
    item_base["valid_delivery_dates"] = item_base.order_delivered_customer_date.notna() & item_base.order_estimated_delivery_date.notna()
    item_base["year_month"] = item_base.purchase_month

    # Seller-order is the attribution grain for service outcomes. Shared orders are
    # intentionally associated with each seller, so seller order counts overlap.
    seller_order = item_base.groupby(["seller_id", "order_id"], as_index=False).agg(
        sales=("price", "sum"), freight=("freight_value", "sum"),
        seller_state=("seller_state", "first"), seller_city=("seller_city", "first"),
        customer_state=("customer_state", "first"), customer_unique_id=("customer_unique_id", "first"),
        purchase_month=("purchase_month", "first"),
        actual_delivery=("order_delivered_customer_date", "first"), estimated_delivery=("order_estimated_delivery_date", "first"),
    )
    seller_order["valid_delivery_dates"] = seller_order.actual_delivery.notna() & seller_order.estimated_delivery.notna()
    seller_order["is_late"] = (
        seller_order.valid_delivery_dates
        & seller_order.actual_delivery.dt.normalize().gt(seller_order.estimated_delivery.dt.normalize())
    )
    seller_order = seller_order.merge(review_orders[["order_id", "review_score"]], on="order_id", how="left", validate="many_to_one")
    seller_order["reviewed"] = seller_order.review_score.notna()
    seller_order["low_rating"] = seller_order.review_score.le(2).fillna(False)

    # G1: all status counts and delivered order summary.
    g1 = scoped.groupby("order_status", as_index=False).agg(order_count=("order_id", "nunique"))
    scope_n = scoped.order_id.nunique()
    g1["order_share"] = g1.order_count / scope_n if scope_n else np.nan
    merch_total = item_base.price.sum()
    delivered_customers = delivered.customer_unique_id.nunique()
    delivered_orders_n = delivered.order_id.nunique()
    g1_summary = pd.DataFrame([{
        "delivered_orders": delivered_orders_n,
        "distinct_customers": delivered_customers,
        "merchandise_sales_brl": merch_total,
        "average_order_value_brl": merch_total / delivered_orders_n if delivered_orders_n else np.nan,
        "sales_definition": "SUM(order_items.price); excludes freight",
    }])
    g1.to_csv(out / "G1_order_status.csv", index=False)
    g1_summary.to_csv(out / "G1_delivered_summary.csv", index=False)

    # G2: complete month series; LAG and running sum are calculated in SQL output logic.
    months = pd.period_range(START, END - pd.Timedelta(days=1), freq="M").astype(str)
    month_base = pd.DataFrame({"purchase_month": months})
    g2_values = delivered.groupby("purchase_month", as_index=False).agg(delivered_orders=("order_id", "nunique"))
    g2_sales = item_base.groupby("purchase_month", as_index=False).agg(merchandise_sales_brl=("price", "sum"))
    g2 = month_base.merge(g2_sales, on="purchase_month", how="left").merge(g2_values, on="purchase_month", how="left").fillna({"merchandise_sales_brl": 0, "delivered_orders": 0})
    g2["average_order_value_brl"] = np.where(g2.delivered_orders.gt(0), g2.merchandise_sales_brl / g2.delivered_orders, np.nan)
    g2["previous_sales_brl"] = g2.merchandise_sales_brl.shift(1)
    g2["sales_growth"] = np.where(g2.previous_sales_brl.gt(0), (g2.merchandise_sales_brl - g2.previous_sales_brl) / g2.previous_sales_brl, np.nan)
    g2["running_sales_brl"] = g2.merchandise_sales_brl.cumsum()
    g2.to_csv(out / "G2_monthly_sales.csv", index=False)

    # G3: review and payment coverage are separate measures.
    pay_orders = set(payments.order_id.dropna().unique())
    review_order_set = set(review_orders.order_id.dropna().unique())
    delivered_ids = set(delivered.order_id)
    month_flags = delivered[["order_id", "purchase_month"]].drop_duplicates().copy()
    month_flags["has_valid_review"] = month_flags.order_id.isin(review_order_set)
    month_flags["has_payment"] = month_flags.order_id.isin(pay_orders)
    g3 = month_flags.groupby("purchase_month", as_index=False).agg(
        delivered_orders=("order_id", "nunique"), valid_review_orders=("has_valid_review", "sum"), payment_orders=("has_payment", "sum"))
    g3["missing_review_orders"] = g3.delivered_orders - g3.valid_review_orders
    g3["review_coverage"] = g3.valid_review_orders / g3.delivered_orders
    g3["missing_payment_orders"] = g3.delivered_orders - g3.payment_orders
    g3["payment_coverage"] = g3.payment_orders / g3.delivered_orders
    g3.to_csv(out / "G3_monthly_coverage.csv", index=False)
    missing_review = month_flags.loc[~month_flags.has_valid_review, ["order_id", "purchase_month"]].head(10)
    missing_payment = month_flags.loc[~month_flags.has_payment, ["order_id", "purchase_month"]].head(10)
    missing_review.assign(missing_record="valid_review").to_csv(out / "G3_missing_review_sample.csv", index=False)
    missing_payment.assign(missing_record="payment").to_csv(out / "G3_missing_payment_sample.csv", index=False)

    # E1 seller ranking.
    e1 = item_base.groupby(["seller_id", "seller_state"], as_index=False).agg(
        merchandise_sales_brl=("price", "sum"), item_count=("order_item_id", "count"), delivered_orders=("order_id", "nunique"))
    e1["marketplace_sales_share"] = e1.merchandise_sales_brl / merch_total if merch_total else np.nan
    e1["sales_rank"] = e1.merchandise_sales_brl.rank(method="min", ascending=False).astype(int)
    e1 = e1.sort_values(["sales_rank", "seller_id"])
    e1.to_csv(out / "E1_seller_ranking.csv", index=False)

    # E2 seller x all 20 months, preserving zero-activity months.
    all_sellers = sellers[["seller_id", "seller_state"]].drop_duplicates()
    seller_month_sales = item_base.groupby(["seller_id", "purchase_month"], as_index=False).agg(merchandise_sales_brl=("price", "sum"), delivered_orders=("order_id", "nunique"))
    e2 = all_sellers.assign(_k=1).merge(pd.DataFrame({"purchase_month": months, "_k": 1}), on="_k").drop(columns="_k")
    e2 = e2.merge(seller_month_sales, on=["seller_id", "purchase_month"], how="left").fillna({"merchandise_sales_brl": 0, "delivered_orders": 0})
    e2 = e2.sort_values(["seller_id", "purchase_month"])
    e2["previous_month_sales_brl"] = e2.groupby("seller_id").merchandise_sales_brl.shift(1)
    e2["sales_growth"] = np.where(e2.previous_month_sales_brl.gt(0), (e2.merchandise_sales_brl - e2.previous_month_sales_brl) / e2.previous_month_sales_brl, np.nan)
    e2["monthly_rank"] = e2.groupby("purchase_month").merchandise_sales_brl.rank(method="min", ascending=False)
    e2.loc[e2.merchandise_sales_brl.eq(0), "monthly_rank"] = np.nan
    e2.to_csv(out / "E2_seller_month.csv", index=False)

    # E3 seller peer benchmark by seller state.
    e3 = e1.copy()
    state_bench = e3.groupby("seller_state", dropna=False).agg(peer_seller_count=("seller_id", "nunique"), state_mean_sales_brl=("merchandise_sales_brl", "mean")).reset_index()
    e3 = e3.merge(state_bench, on="seller_state", how="left")
    e3["difference_from_state_mean_brl"] = e3.merchandise_sales_brl - e3.state_mean_sales_brl
    e3["comparison_flag"] = np.where(e3.peer_seller_count.lt(5), "Limited: fewer than 5 sellers", "Peer group >= 5")
    e3.to_csv(out / "E3_state_peer_comparison.csv", index=False)

    # E4 top five customer states by item sales.
    state_sales = item_base.groupby("customer_state", dropna=False).price.sum().sort_values(ascending=False)
    top_states = list(state_sales.head(5).index)
    e4x = item_base.assign(top_market=item_base.customer_state.isin(top_states))
    e4 = e4x.groupby(["seller_id", "seller_state"], as_index=False).agg(
        total_sales_brl=("price", "sum"), selected_state_sales_brl=("price", lambda x: x[e4x.loc[x.index, "top_market"]].sum()))
    e4["selected_state_share"] = e4.selected_state_sales_brl / e4.total_sales_brl
    e4["selected_states"] = ", ".join(str(x) for x in top_states)
    e4.to_csv(out / "E4_top_customer_markets.csv", index=False)
    pd.DataFrame({"rank": range(1, len(top_states)+1), "customer_state": top_states, "sales_brl": [state_sales[s] for s in top_states]}).to_csv(out / "E4_selected_states.csv", index=False)

    # E5 seller review segments with order-level association.
    e5 = seller_order.groupby("seller_id", as_index=False).agg(
        seller_state=("seller_state", "first"), eligible_orders=("order_id", "nunique"),
        valid_review_orders=("reviewed", "sum"), low_rating_orders=("low_rating", "sum"))
    e5["review_segment"] = np.select(
        [e5.low_rating_orders.gt(0), e5.valid_review_orders.gt(0)],
        ["At least one low-rated order", "Rated orders; no low rating"],
        default="No valid reviews")
    e5_summary = e5.groupby("review_segment", as_index=False).agg(seller_count=("seller_id", "nunique"), eligible_orders=("eligible_orders", "sum"), valid_review_orders=("valid_review_orders", "sum"), low_rating_orders=("low_rating_orders", "sum"))
    e5_summary.to_csv(out / "E5_review_segments.csv", index=False)
    e5.to_csv(out / "E5_seller_review_detail.csv", index=False)

    # E6 period compare for Jan-Jun 2017 vs Jan-Jun 2018.
    p1, p2 = [f"{y}-{m:02d}" for y in [2017, 2018] for m in range(1, 7)][0:6], [f"2018-{m:02d}" for m in range(1, 7)]
    p1_sales = item_base.loc[item_base.purchase_month.isin(p1)].groupby("seller_id").price.sum().rename("sales_jan_jun_2017_brl")
    p2_sales = item_base.loc[item_base.purchase_month.isin(p2)].groupby("seller_id").price.sum().rename("sales_jan_jun_2018_brl")
    e6 = all_sellers.merge(p1_sales, on="seller_id", how="left").merge(p2_sales, on="seller_id", how="left").fillna({"sales_jan_jun_2017_brl": 0, "sales_jan_jun_2018_brl": 0})
    e6["activity_group"] = np.select(
        [e6.sales_jan_jun_2017_brl.gt(0) & e6.sales_jan_jun_2018_brl.gt(0), e6.sales_jan_jun_2017_brl.gt(0), e6.sales_jan_jun_2018_brl.gt(0)],
        ["Active in both", "2017 only", "2018 only"], default="No activity in either period")
    e6.to_csv(out / "E6_period_activity.csv", index=False)

    # E7 seller service scorecard with >=30 eligible seller-orders.
    e7 = seller_order.groupby(["seller_id", "seller_state"], as_index=False).agg(
        eligible_orders=("order_id", "nunique"), sales_brl=("sales", "sum"), freight_brl=("freight", "sum"),
        late_orders=("is_late", "sum"), valid_delivery_date_orders=("valid_delivery_dates", "sum"),
        valid_review_orders=("reviewed", "sum"), low_rating_orders=("low_rating", "sum"))
    e7 = e7.loc[e7.eligible_orders.ge(30)].copy()
    e7["late_delivery_rate"] = e7.late_orders / e7.valid_delivery_date_orders.replace(0, np.nan)
    e7["freight_to_sales_ratio"] = e7.freight_brl / e7.sales_brl.replace(0, np.nan)
    e7["review_coverage"] = e7.valid_review_orders / e7.eligible_orders.replace(0, np.nan)
    e7["low_rating_rate"] = e7.low_rating_orders / e7.valid_review_orders.replace(0, np.nan)
    e7 = e7.merge(e1[["seller_id", "item_count", "sales_rank", "marketplace_sales_share"]], on="seller_id", how="left")
    e7.to_csv(out / "E7_seller_scorecard.csv", index=False)

    # Period-level seller scorecard powers the workbook's month-range and state filters.
    period_defs = {
        "All scope": set(months),
        "Jan-Jun 2017": {f"2017-{m:02d}" for m in range(1, 7)},
        "Jan-Jun 2018": {f"2018-{m:02d}" for m in range(1, 7)},
    }
    period_frames = []
    for period_label, period_months in period_defs.items():
        po = seller_order.loc[seller_order.purchase_month.isin(period_months)]
        p = po.groupby(["seller_id", "seller_state"], as_index=False).agg(
            eligible_orders=("order_id", "nunique"), sales_brl=("sales", "sum"), freight_brl=("freight", "sum"),
            late_orders=("is_late", "sum"), valid_delivery_date_orders=("valid_delivery_dates", "sum"),
            valid_review_orders=("reviewed", "sum"), low_rating_orders=("low_rating", "sum"))
        p["period"] = period_label
        p["late_delivery_rate"] = p.late_orders / p.valid_delivery_date_orders.replace(0, np.nan)
        p["freight_to_sales_ratio"] = p.freight_brl / p.sales_brl.replace(0, np.nan)
        p["review_coverage"] = p.valid_review_orders / p.eligible_orders.replace(0, np.nan)
        p["low_rating_rate"] = p.low_rating_orders / p.valid_review_orders.replace(0, np.nan)
        period_frames.append(p)
    dashboard_seller_period = pd.concat(period_frames, ignore_index=True)
    dashboard_seller_period.to_csv(out / "Dashboard_seller_period.csv", index=False)

    # O1 seller portfolio breadth and top-category concentration.
    seller_cat = item_base.groupby(["seller_id", "category"], as_index=False).price.sum().rename(columns={"price": "category_sales_brl"})
    seller_cat["category_rank"] = seller_cat.groupby("seller_id").category_sales_brl.rank(method="first", ascending=False)
    o1 = seller_cat.groupby("seller_id", as_index=False).agg(category_count=("category", "nunique"), sales_brl=("category_sales_brl", "sum"), top_category_sales_brl=("category_sales_brl", "max"))
    o1["top_category_share"] = o1.top_category_sales_brl / o1.sales_brl
    o1 = o1.merge(e1[["seller_id", "seller_state", "sales_rank"]], on="seller_id", how="left")
    o1["portfolio_breadth_quartile"] = pd.qcut(o1.category_count.rank(method="first"), 4, labels=["Q1 narrow", "Q2", "Q3", "Q4 broad"])
    o1.to_csv(out / "O1_seller_portfolio.csv", index=False)

    # O2 seller revenue concentration among their top 5 unique customers.
    cust_seller = item_base.groupby(["seller_id", "customer_unique_id"], as_index=False).price.sum().rename(columns={"price": "customer_sales_brl"})
    cust_seller["customer_rank"] = cust_seller.groupby("seller_id").customer_sales_brl.rank(method="first", ascending=False)
    o2 = cust_seller.groupby("seller_id", as_index=False).agg(total_sales_brl=("customer_sales_brl", "sum"), distinct_customers=("customer_unique_id", "nunique"), top_five_customer_sales_brl=("customer_sales_brl", lambda s: s[cust_seller.loc[s.index, "customer_rank"].le(5)].sum()))
    o2["top_five_customer_share"] = o2.top_five_customer_sales_brl / o2.total_sales_brl
    o2 = o2.merge(e1[["seller_id", "seller_state", "sales_rank"]], on="seller_id", how="left")
    o2.to_csv(out / "O2_customer_concentration.csv", index=False)

    # Dashboard monthly seller-state aggregation and seller-level results.
    dash_month = item_base.groupby(["purchase_month", "seller_state"], as_index=False).agg(sales_brl=("price", "sum"), active_sellers=("seller_id", "nunique"), seller_orders=("order_id", "nunique"))
    dash_month.to_csv(out / "Dashboard_month_state.csv", index=False)
    e7.to_csv(out / "Dashboard_seller_scorecard.csv", index=False)

    # Compact profiling evidence.
    checks = []
    for key, df in [("customers", customers), ("orders", orders), ("order_items", items), ("order_payments", payments), ("order_reviews", reviews), ("sellers", sellers), ("products", products), ("category_translation", translation)]:
        checks.append({"table": key, "source_rows": len(df)})
    checks = pd.DataFrame(checks)
    checks.to_csv(out / "data_profile_row_counts.csv", index=False)
    multiple_reviews = int(reviews.groupby("order_id").size().gt(1).sum())
    bad_scores = int((~reviews.review_score.between(1, 5)).sum())
    missing_dates = int(delivered.order_delivered_customer_date.isna().sum())
    missing_estimated_dates = int(delivered.order_estimated_delivery_date.isna().sum())
    duplicate_groups = {
        "customers_customer_id": int(customers.duplicated(["customer_id"]).sum()),
        "orders_order_id": int(orders.duplicated(["order_id"]).sum()),
        "items_order_item_id": int(items.duplicated(["order_id", "order_item_id"]).sum()),
        "payments_order_sequence": int(payments.duplicated(["order_id", "payment_sequential"]).sum()),
        "sellers_seller_id": int(sellers.duplicated(["seller_id"]).sum()),
        "products_product_id": int(products.duplicated(["product_id"]).sum()),
        "translation_category": int(translation.duplicated(["product_category_name"]).sum()),
    }
    unmatched = {
        "orders_customer": int((~orders.customer_id.isin(customers.customer_id)).sum()),
        "items_order": int((~items.order_id.isin(orders.order_id)).sum()),
        "items_seller": int((~items.seller_id.isin(sellers.seller_id)).sum()),
        "items_product": int((~items.product_id.isin(products.product_id)).sum()),
        "payments_order": int((~payments.order_id.isin(orders.order_id)).sum()),
        "reviews_order": int((~reviews.order_id.isin(orders.order_id)).sum()),
    }
    metadata = {
        "scope_start_inclusive": "2017-01-01", "scope_end_exclusive": "2018-09-01",
        "scoped_orders": int(scoped.order_id.nunique()), "delivered_orders": int(delivered_orders_n),
        "delivered_distinct_customers": int(delivered_customers), "merchandise_sales_brl": round(float(merch_total), 2),
        "aov_brl": round(float(merch_total / delivered_orders_n), 2) if delivered_orders_n else None,
        "seller_count_with_delivered_item_sales": int(e1.seller_id.nunique()),
        "seller_count_dataset": int(sellers.seller_id.nunique()), "seller_count_e7_min_30": int(e7.seller_id.nunique()),
        "seller_order_rows_attribution": int(len(seller_order)), "seller_order_attribution_overlaps_market_orders": True,
        "orders_with_multiple_source_reviews": multiple_reviews, "invalid_review_score_rows": bad_scores,
        "delivered_orders_missing_actual_delivery_date": missing_dates,
        "delivered_orders_missing_estimated_delivery_date": missing_estimated_dates,
        "candidate_key_duplicate_rows": duplicate_groups,
        "unmatched_foreign_key_rows": unmatched,
        "late_rate_denominator_orders": int(seller_order.valid_delivery_dates.sum()),
        "late_order_count_attributed": int(seller_order.is_late.sum()),
        "top_5_customer_states": [str(x) for x in top_states],
        "note": "Sales are attributed to the seller at item grain. Seller order and service counts overlap when orders contain multiple sellers."
    }
    (out / "project_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
