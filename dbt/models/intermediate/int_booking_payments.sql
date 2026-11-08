-- one row per booking that has any payment activity
with ranked as (
    select
        p.*,
        -- the payment that decided the outcome: a paid/refunded one beats a failed one,
        -- then the latest
        row_number() over (
            partition by booking_id
            order by (payment_status <> 'failed') desc, paid_at desc, payment_id desc
        ) as rn
    from {{ ref('stg_payments') }} p
)

select
    booking_id,
    sum(amount) filter (where payment_status = 'paid')      as paid_amount,
    sum(amount) filter (where payment_status = 'refunded')  as refunded_amount,
    count(*)    filter (where payment_status = 'failed')    as failed_attempts,
    max(payment_method) filter (where rn = 1)               as payment_method,
    max(payment_status) filter (where rn = 1)               as final_payment_status,
    max(paid_at)                                            as last_payment_at
from ranked
group by booking_id
