-- Credit-note quantities and invoice reversal state.
-- Run once in the target database after account_move_new_types_migration.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fnc_account_move_refresh_reversal(
  in_parent_move_id bigint
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  pb_fully_reversed boolean;
  pn_invoice_total numeric;
  pn_applied_amount numeric;
BEGIN
  IF in_parent_move_id IS NULL THEN
    RETURN;
  END IF;

  -- Serialize credit-note confirmations for the same invoice.
  PERFORM 1
  FROM public.account_move
  WHERE move_id = in_parent_move_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Every posted credit-note line must still identify its source by order_id.
  IF EXISTS (
    SELECT 1
    FROM public.account_move credit
    JOIN public.account_move_lines credit_line
      ON credit_line.move_id = credit.move_id
     AND COALESCE(credit_line.type, 'L') = 'L'
    LEFT JOIN public.account_move_lines source_line
      ON source_line.move_id = in_parent_move_id
     AND source_line.position = credit_line.position
     AND COALESCE(source_line.type, 'L') = 'L'
    WHERE credit.parent_id = in_parent_move_id
      AND credit.state = 'posted'
      AND (
        credit.document = 'CN'
        OR credit.document_type = 'credit_note'
        OR credit.type IN ('out_refund', 'in_refund')
      )
      AND source_line.line_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'La nota de crédito contiene una línea que no corresponde a la factura original (%)',
      in_parent_move_id;
  END IF;

  WITH source_quantities AS (
    SELECT
      source_line.line_id,
      GREATEST(COALESCE(source_line.quantity, 0), 0) AS source_quantity,
      reversed.reversed_quantity
    FROM public.account_move_lines source_line
    CROSS JOIN LATERAL (
      SELECT COALESCE(SUM(GREATEST(COALESCE(credit_line.quantity, 0), 0)), 0)
             AS reversed_quantity
      FROM public.account_move credit
      JOIN public.account_move_lines credit_line
        ON credit_line.move_id = credit.move_id
       AND credit_line.position = source_line.position
       AND COALESCE(credit_line.type, 'L') = 'L'
      WHERE credit.parent_id = in_parent_move_id
        AND credit.state = 'posted'
        AND (
          credit.document = 'CN'
          OR credit.document_type = 'credit_note'
          OR credit.type IN ('out_refund', 'in_refund')
        )
    ) reversed
    WHERE source_line.move_id = in_parent_move_id
      AND COALESCE(source_line.type, 'L') = 'L'
  )
  UPDATE public.account_move_lines source_line
  SET
    quantity_reversed = reversed_quantity,
    quantity_to_be_reversed = GREATEST(source_quantity - reversed_quantity, 0)
  FROM source_quantities quantities
  WHERE source_line.line_id = quantities.line_id
    AND (
      source_line.quantity_reversed IS DISTINCT FROM
        quantities.reversed_quantity
      OR source_line.quantity_to_be_reversed IS DISTINCT FROM
        GREATEST(quantities.source_quantity - quantities.reversed_quantity, 0)
    );

  SELECT
    EXISTS (
      SELECT 1
      FROM public.account_move_lines
      WHERE move_id = in_parent_move_id
        AND COALESCE(type, 'L') = 'L'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.account_move_lines
      WHERE move_id = in_parent_move_id
        AND COALESCE(type, 'L') = 'L'
        AND COALESCE(quantity_to_be_reversed, GREATEST(COALESCE(quantity, 0), 0)) > 0
    )
  INTO pb_fully_reversed;

  IF pb_fully_reversed THEN
    UPDATE public.account_move
    SET
      reversed = B'1',
      payment_state = 'reversed',
      amount_to_be_paid = 0
    WHERE move_id = in_parent_move_id
      AND (
        reversed IS DISTINCT FROM B'1'
        OR payment_state IS DISTINCT FROM 'reversed'
        OR amount_to_be_paid IS DISTINCT FROM 0
      );
  ELSE
    -- If a full reversal was undone, recover the real payment state from the bridge.
    SELECT
      GREATEST(COALESCE(move.amount_withtaxed, 0), 0),
      LEAST(
        GREATEST(COALESCE(SUM(link.amount), 0), 0),
        GREATEST(COALESCE(move.amount_withtaxed, 0), 0)
      )
    INTO pn_invoice_total, pn_applied_amount
    FROM public.account_move move
    LEFT JOIN public.payment_account_move link ON link.move_id = move.move_id
    WHERE move.move_id = in_parent_move_id
    GROUP BY move.amount_withtaxed;

    UPDATE public.account_move
    SET
      reversed = B'0',
      amount_paid = CASE
        WHEN payment_state = 'reversed' THEN pn_applied_amount
        ELSE amount_paid
      END,
      amount_to_be_paid = CASE
        WHEN payment_state = 'reversed' THEN GREATEST(pn_invoice_total - pn_applied_amount, 0)
        ELSE amount_to_be_paid
      END,
      payment_state = CASE
        WHEN payment_state <> 'reversed' THEN payment_state
        WHEN pn_applied_amount >= pn_invoice_total AND pn_invoice_total > 0 THEN 'paid'
        WHEN pn_applied_amount > 0 THEN 'partial'
        ELSE 'not_paid'
      END
    WHERE move_id = in_parent_move_id
      AND (reversed IS DISTINCT FROM B'0' OR payment_state = 'reversed');
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_fnc_account_move_refresh_reversal()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  pn_old_parent_id bigint;
  pn_new_parent_id bigint;
BEGIN
  IF TG_OP <> 'INSERT'
     AND OLD.parent_id IS NOT NULL
     AND (
       OLD.document = 'CN'
       OR OLD.document_type = 'credit_note'
       OR OLD.type IN ('out_refund', 'in_refund')
     ) THEN
    pn_old_parent_id := OLD.parent_id;
  END IF;

  IF TG_OP <> 'DELETE'
     AND NEW.parent_id IS NOT NULL
     AND (
       NEW.document = 'CN'
       OR NEW.document_type = 'credit_note'
       OR NEW.type IN ('out_refund', 'in_refund')
     ) THEN
    pn_new_parent_id := NEW.parent_id;
  END IF;

  IF pn_old_parent_id IS NOT NULL THEN
    PERFORM public.fnc_account_move_refresh_reversal(pn_old_parent_id);
  END IF;

  IF pn_new_parent_id IS NOT NULL
     AND pn_new_parent_id IS DISTINCT FROM pn_old_parent_id THEN
    PERFORM public.fnc_account_move_refresh_reversal(pn_new_parent_id);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tgr_account_move_refresh_reversal ON public.account_move;
CREATE TRIGGER tgr_account_move_refresh_reversal
AFTER INSERT OR DELETE OR UPDATE OF state, parent_id, document, document_type, type
ON public.account_move
FOR EACH ROW
EXECUTE FUNCTION public.trg_fnc_account_move_refresh_reversal();

CREATE OR REPLACE FUNCTION public.trg_fnc_account_move_lines_refresh_reversal()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  pn_old_parent_id bigint;
  pn_new_parent_id bigint;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    SELECT move.parent_id
    INTO pn_old_parent_id
    FROM public.account_move move
    WHERE move.move_id = OLD.move_id
      AND move.parent_id IS NOT NULL
      AND (
        move.document = 'CN'
        OR move.document_type = 'credit_note'
        OR move.type IN ('out_refund', 'in_refund')
      );
  END IF;

  IF TG_OP <> 'DELETE' THEN
    SELECT move.parent_id
    INTO pn_new_parent_id
    FROM public.account_move move
    WHERE move.move_id = NEW.move_id
      AND move.parent_id IS NOT NULL
      AND (
        move.document = 'CN'
        OR move.document_type = 'credit_note'
        OR move.type IN ('out_refund', 'in_refund')
      );
  END IF;

  IF pn_old_parent_id IS NOT NULL THEN
    PERFORM public.fnc_account_move_refresh_reversal(pn_old_parent_id);
  END IF;

  IF pn_new_parent_id IS NOT NULL
     AND pn_new_parent_id IS DISTINCT FROM pn_old_parent_id THEN
    PERFORM public.fnc_account_move_refresh_reversal(pn_new_parent_id);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tgr_account_move_lines_refresh_reversal
ON public.account_move_lines;
CREATE TRIGGER tgr_account_move_lines_refresh_reversal
AFTER INSERT OR DELETE OR UPDATE OF move_id, position, quantity, type
ON public.account_move_lines
FOR EACH ROW
EXECUTE FUNCTION public.trg_fnc_account_move_lines_refresh_reversal();

-- Recalculate invoices that already have credit notes.
DO $block$
DECLARE
  parent record;
BEGIN
  FOR parent IN
    SELECT DISTINCT move.parent_id
    FROM public.account_move move
    WHERE move.parent_id IS NOT NULL
      AND (
        move.document = 'CN'
        OR move.document_type = 'credit_note'
        OR move.type IN ('out_refund', 'in_refund')
      )
  LOOP
    PERFORM public.fnc_account_move_refresh_reversal(parent.parent_id);
  END LOOP;
END;
$block$;

COMMIT;

-- Verification: a fully credited invoice must have reversed = 1 and remaining = 0.
SELECT
  invoice.move_id,
  invoice.name,
  invoice.reversed,
  invoice.payment_state,
  invoice.amount_to_be_paid,
  line.position,
  line.quantity,
  line.quantity_reversed,
  line.quantity_to_be_reversed
FROM public.account_move invoice
JOIN public.account_move_lines line ON line.move_id = invoice.move_id
WHERE invoice.move_id IN (
  SELECT DISTINCT parent_id
  FROM public.account_move
  WHERE parent_id IS NOT NULL
    AND (
      document = 'CN'
      OR document_type = 'credit_note'
      OR type IN ('out_refund', 'in_refund')
    )
)
ORDER BY invoice.move_id, line.position;
