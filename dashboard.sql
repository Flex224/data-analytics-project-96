WITH visitors_with_leads AS (
    SELECT DISTINCT ON (s.visitor_id)
        s.visitor_id,
        s.visit_date,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign
    FROM
        sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE
        s.medium <> 'organic'
    ORDER BY
        s.visitor_id ASC, s.visit_date DESC
),

utm_aggregates AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        DATE(visit_date) AS visit_date,
        COUNT(visitor_id) AS visitors_count,
        COUNT(CASE WHEN created_at IS NOT NULL THEN visitor_id END)
            AS leads_count,
        COUNT(CASE WHEN status_id = 142 THEN visitor_id END) AS purchases_count,
        SUM(CASE WHEN status_id = 142 THEN amount END) AS revenue
    FROM
        visitors_with_leads
    GROUP BY
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
),

ad_costs AS (
    SELECT
        DATE(campaign_date) AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM
        ya_ads
    GROUP BY
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
    UNION ALL
    SELECT
        DATE(campaign_date) AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM
        vk_ads
    GROUP BY
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
),

final AS (
    SELECT
        u.visit_date,
        u.utm_source,
        u.utm_medium,
        u.utm_campaign,
        u.visitors_count,
        u.leads_count,
        u.purchases_count,
        COALESCE(a.total_cost, 0) AS total_cost,
        COALESCE(u.revenue, 0) AS revenue
    FROM
        utm_aggregates AS u
    LEFT JOIN
        ad_costs AS a
        ON
            u.visit_date = a.visit_date
            AND u.utm_source = a.utm_source
            AND u.utm_medium = a.utm_medium
            AND u.utm_campaign = a.utm_campaign
)

SELECT
    visit_date,
    utm_source,
    utm_medium,
    utm_campaign,
    visitors_count,
    leads_count,
    purchases_count,
    total_cost,
    revenue
FROM
    final
WHERE
    visitors_count > 0;

-- платный и органический трафик
SELECT
    COUNT(DISTINCT CASE WHEN medium <> 'organic' THEN visitor_id END)
        AS paid_visitors,
    COUNT(DISTINCT CASE WHEN medium = 'organic' THEN visitor_id END)
        AS organic_visitors,
    DATE(visit_date) AS visit_day
FROM
    sessions
GROUP BY
    visit_day
ORDER BY
    visit_day ASC;

-- Трафик по всем каналам
SELECT
    source,
    DATE(visit_date) AS visit_day,
    COUNT(DISTINCT visitor_id) AS total_visitors
FROM
    sessions
GROUP BY
    source, visit_day
ORDER BY
    visit_day ASC, source ASC;

-- Эффективность рекламных кампаний
SELECT
    utm_source,
    utm_medium,
    utm_campaign,
    SUM(visitors_count) AS visitors_count,
    SUM(leads_count) AS leads_count,
    SUM(purchases_count) AS purchases_count,
    SUM(total_cost) AS total_cost,
    SUM(revenue) AS revenue,
    ROUND(SUM(total_cost) / NULLIF(SUM(visitors_count), 0), 2) AS cpu,
    ROUND(SUM(total_cost) / NULLIF(SUM(leads_count), 0), 2) AS cpl,
    ROUND(SUM(total_cost) / NULLIF(SUM(purchases_count), 0), 2) AS cppu,
    ROUND(
        (SUM(revenue) - SUM(total_cost)) * 100.0 / NULLIF(SUM(total_cost), 0), 2
    ) AS roi
FROM
    final
GROUP BY
    utm_source,
    utm_medium,
    utm_campaign
ORDER BY
    roi DESC NULLS LAST;

-- Эффективность рекламных каналов
SELECT
    utm_source,
    SUM(visitors_count) AS visitors_count,
    SUM(leads_count) AS leads_count,
    SUM(purchases_count) AS purchases_count,
    SUM(total_cost) AS total_cost,
    SUM(revenue) AS revenue,
    ROUND(SUM(total_cost) / NULLIF(SUM(visitors_count), 0), 2) AS cpu,
    ROUND(SUM(total_cost) / NULLIF(SUM(leads_count), 0), 2) AS cpl,
    ROUND(SUM(total_cost) / NULLIF(SUM(purchases_count), 0), 2) AS cppu,
    ROUND(
        (SUM(revenue) - SUM(total_cost)) * 100.0 / NULLIF(SUM(total_cost), 0), 2
    ) AS roi
FROM
    final
GROUP BY
    utm_source
HAVING
    SUM(purchases_count) > 0
ORDER BY
    roi DESC NULLS LAST;

-- воронка конверсий
WITH aggregated_data AS (
    SELECT
        COUNT(visitor_id) AS visitors,
        COUNT(lead_id) AS leads,
        COUNT(CASE WHEN status_id = 142 THEN 1 END) AS purchases
    FROM
        visitors_with_leads
),

funnel_stages AS (
    SELECT
        'Visitors' AS conversion_stage,
        1 AS sort_order
    UNION ALL
    SELECT
        'Leads' AS conversion_stage,
        2 AS sort_order
    UNION ALL
    SELECT
        'Purchases' AS conversion_stage,
        3 AS sort_order
),

funnel_values AS (
    SELECT
        visitors AS total_count,
        1 AS sort_order
    FROM aggregated_data
    UNION ALL
    SELECT
        leads AS total_count,
        2 AS sort_order
    FROM aggregated_data
    UNION ALL
    SELECT
        purchases AS total_count,
        3 AS sort_order
    FROM aggregated_data
)

SELECT
    s.conversion_stage,
    v.total_count
FROM
    funnel_stages AS s
INNER JOIN
    funnel_values AS v
    ON s.sort_order = v.sort_order
ORDER BY
    s.sort_order;
