-- Ejecutar exclusivamente por el DBA.
-- Corrige la conciliación después del cambio amount_residual -> amount_to_be_paid.

BEGIN;

CREATE OR REPLACE FUNCTION public.fnc_payment_account_move(
  in_payment_account_move__payment_id bigint,
  in_payment_account_move__move_id bigint,
  in_payment_account_move__amount double precision
)
RETURNS TABLE(oj_info jsonb, oj_data jsonb)
LANGUAGE plpgsql
AS $function$
DECLARE
  pr_payment public.payment%ROWTYPE;
  pr_move public.account_move%ROWTYPE;
  pn_existing_amount public.payment_account_move.amount%TYPE;
  pn_linked_amount public.payment_account_move.amount%TYPE;
  pn_requested_amount public.payment.amount%TYPE;
  pn_applied_amount public.payment_account_move.amount%TYPE;
  pn_amount_paid public.account_move.amount_paid%TYPE;
  pn_amount_to_be_paid public.account_move.amount_to_be_paid%TYPE;
  pt_payment_state public.account_move.payment_state%TYPE;
BEGIN
  SELECT payment.*
  INTO pr_payment
  FROM public.payment
  WHERE payment_id = in_payment_account_move__payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe el pago %', in_payment_account_move__payment_id;
  END IF;

  SELECT account_move.*
  INTO pr_move
  FROM public.account_move
  WHERE move_id = in_payment_account_move__move_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la factura %', in_payment_account_move__move_id;
  END IF;

  SELECT amount
  INTO pn_existing_amount
  FROM public.payment_account_move
  WHERE payment_id = in_payment_account_move__payment_id
    AND move_id = in_payment_account_move__move_id
  LIMIT 1;

  IF FOUND THEN
    oj_info := fnc_config_message(202, 'El pago ya estaba aplicado.', NULL);
    oj_data := jsonb_build_object(
      'payment_id', in_payment_account_move__payment_id,
      'move_id', in_payment_account_move__move_id,
      'amount', pn_existing_amount
    );
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT COALESCE(SUM(amount), 0)
  INTO pn_linked_amount
  FROM public.payment_account_move
  WHERE move_id = in_payment_account_move__move_id;

  pn_amount_paid := GREATEST(
    COALESCE(pr_move.amount_paid, 0),
    COALESCE(pn_linked_amount, 0)
  );
  pn_amount_to_be_paid := GREATEST(
    COALESCE(pr_move.amount_withtaxed, 0) - pn_amount_paid,
    0
  );
  pn_requested_amount := COALESCE(
    NULLIF(in_payment_account_move__amount, 0),
    NULLIF(pr_payment.amount_residual, 0),
    pr_payment.amount,
    0
  );

  IF pn_requested_amount <= 0 THEN
    RAISE EXCEPTION 'El pago % no tiene importe disponible', in_payment_account_move__payment_id;
  END IF;

  IF pn_amount_to_be_paid <= 0 THEN
    RAISE EXCEPTION 'La factura % no tiene deuda pendiente', in_payment_account_move__move_id;
  END IF;

  pn_applied_amount := LEAST(pn_requested_amount, pn_amount_to_be_paid);
  pn_amount_paid := pn_amount_paid + pn_applied_amount;
  pn_amount_to_be_paid := GREATEST(
    COALESCE(pr_move.amount_withtaxed, 0) - pn_amount_paid,
    0
  );
  pt_payment_state := CASE
    WHEN pn_amount_to_be_paid = 0 THEN 'paid'
    ELSE 'partial'
  END;

  INSERT INTO public.payment_account_move (payment_id, move_id, amount)
  VALUES (
    in_payment_account_move__payment_id,
    in_payment_account_move__move_id,
    pn_applied_amount
  );

  UPDATE public.account_move
  SET
    amount_paid = pn_amount_paid,
    amount_to_be_paid = pn_amount_to_be_paid,
    payment_state = pt_payment_state
  WHERE move_id = in_payment_account_move__move_id;

  UPDATE public.payment
  SET
    move_id = NULL,
    amount_residual = GREATEST(COALESCE(pr_payment.amount, pn_requested_amount) - pn_applied_amount, 0)
  WHERE payment_id = in_payment_account_move__payment_id;

  oj_info := fnc_config_message(202, 'Pago aplicado a la factura.', NULL);
  oj_data := jsonb_build_object(
    'payment_id', in_payment_account_move__payment_id,
    'move_id', in_payment_account_move__move_id,
    'amount', pn_applied_amount,
    'amount_paid', pn_amount_paid,
    'amount_to_be_paid', pn_amount_to_be_paid,
    'payment_state', pt_payment_state
  );
  RETURN NEXT;
END;
$function$;

-- Repara pagos conocidos sólo si todavía existen ambos registros.
DO $block$
BEGIN
  IF EXISTS (SELECT 1 FROM public.payment WHERE payment_id = 57)
     AND EXISTS (SELECT 1 FROM public.account_move WHERE move_id = 187)
     AND NOT EXISTS (
       SELECT 1
       FROM public.payment_account_move
       WHERE payment_id = 57 AND move_id = 187
     ) THEN
    PERFORM * FROM public.fnc_payment_account_move(57, 187, 16);
  END IF;

  IF EXISTS (SELECT 1 FROM public.payment WHERE payment_id = 58)
     AND EXISTS (SELECT 1 FROM public.account_move WHERE move_id = 188)
     AND NOT EXISTS (
       SELECT 1
       FROM public.payment_account_move
       WHERE payment_id = 58 AND move_id = 188
     ) THEN
    PERFORM * FROM public.fnc_payment_account_move(58, 188, 1.18);
  END IF;
END;
$block$;

COMMIT;

SELECT payment_id, move_id, amount
FROM public.payment_account_move
WHERE (payment_id = 57 AND move_id = 187)
   OR (payment_id = 58 AND move_id = 188)
ORDER BY payment_id;

SELECT move_id, amount_withtaxed, amount_paid, amount_to_be_paid, payment_state
FROM public.account_move
WHERE move_id IN (187, 188)
ORDER BY move_id;
