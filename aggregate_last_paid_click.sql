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
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON
            s.visitor_id = l.visitor_id
            AND s.visit_date <= l.created_at
    WHERE s.medium != 'organic'
    ORDER BY s.visitor_id ASC, s.visit_date DESC
),

utm_aggregates AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        DATE(visit_date) AS visit_date,
        COUNT(visitor_id) AS visitors_count,
        COUNT(
            CASE
                WHEN created_at IS NOT NULL THEN visitor_id
            END
        ) AS leads_count,
        COUNT(CASE WHEN status_id = 142 THEN 1 END) AS purchases_count,
        SUM(CASE WHEN status_id = 142 THEN amount END) AS revenue
    FROM visitors_with_leads
    GROUP BY
        utm_source,
        utm_medium,
        utm_campaign,
        DATE(visit_date)
),

ad_costs AS (
    SELECT
        DATE(campaign_date) AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY
        DATE(campaign_date),
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
    FROM vk_ads
    GROUP BY
        DATE(campaign_date),
        utm_source,
        utm_medium,
        utm_campaign
)

SELECT
    u.visit_date,
    u.visitors_count,
    u.utm_source,
    u.utm_medium,
    u.utm_campaign,
    a.total_cost,
    u.leads_count,
    u.purchases_count,
    u.revenue
FROM utm_aggregates AS u
LEFT JOIN ad_costs AS a
    ON
        u.visit_date = a.visit_date
        AND u.utm_source = a.utm_source
        AND u.utm_medium = a.utm_medium
        AND u.utm_campaign = a.utm_campaign
ORDER BY
    u.revenue DESC NULLS LAST,
    u.visit_date ASC,
    u.utm_source DESC,
    u.utm_medium ASC,
    u.utm_campaign ASC,
    u.visitors_count ASC
LIMIT 15;
