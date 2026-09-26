-- Ejecutar exclusivamente por el DBA después de revisar el respaldo.
-- Este script no modifica estructuras eliminadas ni trata el campo sequence.

BEGIN;

ALTER TABLE public.account_move
  ALTER COLUMN payment_state SET DEFAULT 'not_paid',
  ALTER COLUMN email_sent_state SET DEFAULT 'unsent';

UPDATE public.account_move
SET state = CASE upper(state)
  WHEN 'B' THEN 'draft'
  WHEN 'D' THEN 'draft'
  WHEN 'R' THEN 'posted'
  WHEN 'C' THEN 'cancel'
  WHEN 'ER' THEN 'cancel'
  ELSE state
END
WHERE state IS NOT NULL
  AND upper(state) IN ('B', 'D', 'R', 'C', 'ER');

UPDATE public.account_move
SET payment_state = CASE upper(payment_state)
  WHEN 'N' THEN 'not_paid'
  WHEN 'PE' THEN 'not_paid'
  WHEN 'R' THEN 'partial'
  WHEN 'PP' THEN 'partial'
  WHEN 'P' THEN 'paid'
  WHEN 'PF' THEN 'paid'
  ELSE payment_state
END
WHERE payment_state IS NOT NULL
  AND upper(payment_state) IN ('N', 'PE', 'R', 'PP', 'P', 'PF');

UPDATE public.account_move
SET email_sent_state = CASE upper(email_sent_state)
  WHEN 'U' THEN 'unsent'
  WHEN 'S' THEN 'sent'
  ELSE email_sent_state
END
WHERE email_sent_state IS NOT NULL
  AND upper(email_sent_state) IN ('U', 'S');

-- Reconstruye los saldos con la tabla puente, que es la fuente real de pagos aplicados.
WITH linked_payments AS (
  SELECT move_id, COALESCE(SUM(amount), 0) AS amount_paid
  FROM public.payment_account_move
  GROUP BY move_id
),
normalized_balances AS (
  SELECT
    move.move_id,
    LEAST(
      GREATEST(COALESCE(linked.amount_paid, 0), 0),
      GREATEST(COALESCE(move.amount_withtaxed, 0), 0)
    ) AS amount_paid,
    GREATEST(
      COALESCE(move.amount_withtaxed, 0) - COALESCE(linked.amount_paid, 0),
      0
    ) AS amount_to_be_paid
  FROM public.account_move move
  LEFT JOIN linked_payments linked ON linked.move_id = move.move_id
  WHERE move.state <> 'cancel'
    AND COALESCE(move.payment_state, 'not_paid') <> 'reversed'
    AND COALESCE(move.amount_withtaxed, 0) >= 0
)
UPDATE public.account_move move
SET
  amount_paid = balances.amount_paid,
  amount_to_be_paid = balances.amount_to_be_paid,
  payment_state = CASE
    WHEN balances.amount_to_be_paid = 0 AND balances.amount_paid > 0 THEN 'paid'
    WHEN balances.amount_paid > 0 THEN 'partial'
    ELSE 'not_paid'
  END
FROM normalized_balances balances
WHERE balances.move_id = move.move_id;

COMMIT;

SELECT state, COUNT(*)
FROM public.account_move
GROUP BY state
ORDER BY state;

SELECT payment_state, COUNT(*)
FROM public.account_move
GROUP BY payment_state
ORDER BY payment_state;

SELECT email_sent_state, COUNT(*)
FROM public.account_move
GROUP BY email_sent_state
ORDER BY email_sent_state;
