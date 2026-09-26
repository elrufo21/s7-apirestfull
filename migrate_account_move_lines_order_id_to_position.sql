-- Migración: Renombrar order_id a position en account_move_lines
-- y actualizar triggers y funciones relacionadas

BEGIN;

-- 1. Renombrar columna en account_move_lines si aún no ha sido renombrada
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'account_move_lines' 
      AND column_name = 'order_id'
  ) AND NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'account_move_lines' 
      AND column_name = 'position'
  ) THEN
    ALTER TABLE public.account_move_lines RENAME COLUMN order_id TO position;
  END IF;
END $$;

-- 2. Recrear el trigger tgr_account_move_lines_refresh_reversal con position
DROP TRIGGER IF EXISTS tgr_account_move_lines_refresh_reversal ON public.account_move_lines;

CREATE TRIGGER tgr_account_move_lines_refresh_reversal
AFTER INSERT OR DELETE OR UPDATE OF move_id, position, quantity, type
ON public.account_move_lines
FOR EACH ROW
EXECUTE FUNCTION public.trg_fnc_account_move_lines_refresh_reversal();

-- 3. Actualizar función de reversión de notas de crédito fnc_account_move_refresh_reversal
CREATE OR REPLACE FUNCTION public.fnc_account_move_refresh_reversal(in_parent_move_id bigint)
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

  -- Every posted credit-note line must still identify its source by position.
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

-- 4. Actualizar fnc_sale_order_create_invoice para insertar en position en account_move_lines
CREATE OR REPLACE FUNCTION public.fnc_sale_order_create_invoice(
  in_user_id integer,
  in_group_id integer,
  ij_companies jsonb,
  it_action text,
  ij_data jsonb
)
RETURNS TABLE(oj_info jsonb, oj_data jsonb, oj_gby_data jsonb, oj_audit jsonb, oj_stat jsonb)
LANGUAGE plpgsql
AS $function$
DECLARE
  pr_order public.sale_order%ROWTYPE;
  pr_line record;
  pn_order_id bigint;
  pn_move_id bigint;
  pn_move_line_id bigint;
  pn_journal_id bigint;
  pn_document_type_id bigint;
  pn_invoice_quantity double precision;
  pn_ratio double precision;
  pn_line_untaxed_total double precision;
  pn_line_tax_total double precision;
  pn_line_withtaxed_total double precision;
  pn_amount_untaxed double precision := 0;
  pn_amount_tax double precision := 0;
  pn_amount_withtaxed double precision := 0;
  pn_lines_count integer := 0;
  pb_has_invoice_lines boolean := false;
  pt_message_text text;
BEGIN
  pn_order_id := NULLIF(ij_data->>'order_id', '')::bigint;

  IF pn_order_id IS NULL THEN
    RAISE EXCEPTION 'Falta el id de la orden de venta';
  END IF;

  SELECT *
  INTO pr_order
  FROM public.sale_order so
  WHERE so.order_id = pn_order_id
    AND so.group_id = in_group_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la orden de venta % para el grupo %', pn_order_id, in_group_id;
  END IF;

  IF pr_order.state NOT IN ('D', 'S', 'R') THEN
    RAISE EXCEPTION 'La orden de venta % debe estar en borrador, enviada u orden de venta para crear factura', pn_order_id;
  END IF;

  IF pr_order.customer_id IS NULL THEN
    RAISE EXCEPTION 'La orden de venta % no tiene cliente', pn_order_id;
  END IF;

  IF pr_order.currency_id IS NULL THEN
    RAISE EXCEPTION 'La orden de venta % no tiene moneda', pn_order_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.account_move_lines aml
    INNER JOIN public.account_move am
      ON am.move_id = aml.move_id
    INNER JOIN public.sale_order_lines sol
      ON sol.line_id = aml.sale_order_line_id
    WHERE sol.order_id = pn_order_id
      AND am.group_id = in_group_id
      AND am.state = 'draft'
  ) THEN
    RAISE EXCEPTION 'La orden de venta % ya tiene una factura borrador pendiente', pn_order_id;
  END IF;

  pb_has_invoice_lines :=
    ij_data ? 'invoice_lines'
    AND jsonb_typeof(ij_data->'invoice_lines') = 'array'
    AND jsonb_array_length(ij_data->'invoice_lines') > 0;

  IF pb_has_invoice_lines AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(ij_data->'invoice_lines') item
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.sale_order_lines sol
      WHERE sol.order_id = pn_order_id
        AND sol.line_id = NULLIF(item->>'line_id', '')::bigint
    )
  ) THEN
    RAISE EXCEPTION 'Una o más líneas no pertenecen a la orden de venta %', pn_order_id;
  END IF;

  SELECT j.journal_id
  INTO pn_journal_id
  FROM public.journal j
  WHERE j.group_id = in_group_id
    AND j.state = 'A'
    AND j.type = 'SA'
    AND (j.currency_id = pr_order.currency_id OR j.currency_id IS NULL)
    AND (pr_order.company_id IS NULL OR j.company_id = pr_order.company_id)
  ORDER BY
    CASE WHEN j.company_id = pr_order.company_id THEN 0 ELSE 1 END,
    COALESCE(j.order_id, 0),
    j.journal_id
  LIMIT 1;

  IF pn_journal_id IS NULL THEN
    RAISE EXCEPTION 'No existe un diario de ventas activo para la orden %', pn_order_id;
  END IF;

  pn_document_type_id := 1;

  INSERT INTO public.account_move (
    group_id,
    company_id,
    state,
    creation_user,
    creation_date,
    type,
    name,
    partner_id,
    date,
    date_due,
    payment_reference,
    payment_term_id,
    currency_id,
    reference,
    seller_id,
    bank_account_id,
    delivery_date,
    terms_and_conditions,
    amount_tax,
    amount_untaxed,
    amount_withtaxed,
    amount_to_be_paid,
    journal_id,
    document_type_id,
    document_number,
    edi_c51_id,
    edi_state,
    payment_state,
    email_sent_state,
    amount_paid,
    files,
    edi_sent,
    document,
    document_type
  )
  VALUES (
    pr_order.group_id,
    pr_order.company_id,
    'draft',
    in_user_id,
    CURRENT_TIMESTAMP,
    'out_invoice',
    NULL,
    pr_order.customer_id,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    pr_order.name,
    pr_order.payment_term_id,
    pr_order.currency_id,
    pr_order.name,
    pr_order.seller_id,
    NULL,
    NULL,
    pr_order.terms_and_conditions,
    0,
    0,
    0,
    0,
    pn_journal_id,
    pn_document_type_id,
    NULL,
    NULL,
    'P',
    'not_paid',
    'unsent',
    0,
    '[]'::jsonb,
    'U',
    'I',
    'invoice'
  )
  RETURNING move_id INTO pn_move_id;

  FOR pr_line IN
    WITH requested_lines AS (
      SELECT
        NULLIF(item->>'line_id', '')::bigint AS line_id,
        SUM(NULLIF(item->>'quantity', '')::double precision) AS quantity_to_invoice
      FROM jsonb_array_elements(
        CASE WHEN pb_has_invoice_lines THEN ij_data->'invoice_lines' ELSE '[]'::jsonb END
      ) item
      GROUP BY NULLIF(item->>'line_id', '')::bigint
    )
    SELECT
      sol.*,
      GREATEST(
        COALESCE(sol.quantity, 0) - COALESCE(sol.invoiced_total, 0),
        0
      ) AS quantity_residual,
      CASE
        WHEN pb_has_invoice_lines THEN COALESCE(req.quantity_to_invoice, 0)
        ELSE GREATEST(
          COALESCE(sol.quantity, 0) - COALESCE(sol.invoiced_total, 0),
          0
        )
      END AS quantity_to_invoice
    FROM public.sale_order_lines sol
    LEFT JOIN requested_lines req
      ON req.line_id = sol.line_id
    WHERE sol.order_id = pn_order_id
      AND GREATEST(
        COALESCE(sol.quantity, 0) - COALESCE(sol.invoiced_total, 0),
        0
      ) > 0
      AND (
        NOT pb_has_invoice_lines
        OR COALESCE(req.quantity_to_invoice, 0) > 0
      )
    ORDER BY sol.sequence NULLS LAST, sol.line_id
    FOR UPDATE OF sol
  LOOP
    pn_invoice_quantity := COALESCE(pr_line.quantity_to_invoice, 0);

    IF COALESCE(pr_line.quantity, 0) <= 0 THEN
      RAISE EXCEPTION 'La línea % tiene una cantidad inválida', pr_line.line_id;
    END IF;

    IF pn_invoice_quantity - COALESCE(pr_line.quantity_residual, 0) > 0.000001 THEN
      RAISE EXCEPTION 'La cantidad a facturar de la línea % supera el pendiente', pr_line.line_id;
    END IF;

    pn_lines_count := pn_lines_count + 1;
    pn_ratio := pn_invoice_quantity / pr_line.quantity;

    pn_line_untaxed_total :=
      COALESCE(pr_line.amount_subtotal_total * pn_ratio, pr_line.amount_subtotal * pn_invoice_quantity, 0);

    pn_line_tax_total :=
      COALESCE(pr_line.amount_tax_total * pn_ratio, pr_line.amount_tax * pn_invoice_quantity, 0);

    pn_line_withtaxed_total :=
      COALESCE(pr_line.amount_total_total * pn_ratio, pn_line_untaxed_total + pn_line_tax_total, 0);

    INSERT INTO public.account_move_lines (
      sale_order_line_id,
      move_id,
      position,
      product_id,
      label,
      quantity,
      uom_id,
      price_unit,
      amount_tax,
      amount_untaxed,
      amount_withtaxed,
      type,
      notes,
      amount_untaxed_total,
      amount_tax_total,
      amount_withtaxed_total
    )
    VALUES (
      pr_line.line_id,
      pn_move_id,
      pr_line.sequence,
      pr_line.product_id,
      pr_line.label,
      pn_invoice_quantity,
      pr_line.uom_id,
      pr_line.price_unit,
      COALESCE(pr_line.amount_tax, 0),
      COALESCE(pr_line.amount_subtotal, 0),
      COALESCE(pr_line.amount_total, 0),
      pr_line.type,
      pr_line.notes,
      pn_line_untaxed_total,
      pn_line_tax_total,
      pn_line_withtaxed_total
    )
    RETURNING line_id INTO pn_move_line_id;

    INSERT INTO public.account_move_lines_taxes (
      line_id,
      tax_id,
      percentage,
      amount
    )
    SELECT
      pn_move_line_id,
      solt.tax_id,
      solt.percentage,
      COALESCE(solt.amount, 0) * pn_ratio
    FROM public.sale_order_lines_taxes solt
    WHERE solt.line_id = pr_line.line_id;

    pn_amount_untaxed := pn_amount_untaxed + pn_line_untaxed_total;
    pn_amount_tax := pn_amount_tax + pn_line_tax_total;
    pn_amount_withtaxed := pn_amount_withtaxed + pn_line_withtaxed_total;
  END LOOP;

  IF pn_lines_count = 0 THEN
    RAISE EXCEPTION 'La orden de venta % no tiene cantidades pendientes por facturar', pn_order_id;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('account_move_taxes.tax_id'));

  INSERT INTO public.account_move_taxes (
    move_id,
    tax_group_id,
    amount,
    tax_id
  )
  WITH grouped_taxes AS (
    SELECT
      tx.tax_group_id,
      SUM(COALESCE(amlt.amount, 0)) AS amount
    FROM public.account_move_lines aml
    INNER JOIN public.account_move_lines_taxes amlt
      ON amlt.line_id = aml.line_id
    INNER JOIN public.tax tx
      ON tx.tax_id = amlt.tax_id
    WHERE aml.move_id = pn_move_id
    GROUP BY tx.tax_group_id
  ),
  tax_id_base AS (
    SELECT COALESCE(MAX(amt.tax_id), 0) AS max_tax_id
    FROM public.account_move_taxes amt
  )
  SELECT
    pn_move_id,
    grouped_taxes.tax_group_id,
    grouped_taxes.amount,
    tax_id_base.max_tax_id + ROW_NUMBER() OVER (ORDER BY grouped_taxes.tax_group_id)
  FROM grouped_taxes
  CROSS JOIN tax_id_base;

  UPDATE public.account_move
  SET
    amount_untaxed = pn_amount_untaxed,
    amount_tax = pn_amount_tax,
    amount_withtaxed = pn_amount_withtaxed,
    amount_to_be_paid = pn_amount_withtaxed,
    amount_paid = 0,
    payment_state = 'not_paid',
    modification_user = in_user_id,
    modification_date = CURRENT_TIMESTAMP
  WHERE move_id = pn_move_id;

  UPDATE public.sale_order
  SET
    state = 'R',
    modification_user = in_user_id,
    modification_date = CURRENT_TIMESTAMP
  WHERE order_id = pn_order_id;

  PERFORM *
  FROM public.fnc_sale_order_audit_insert(
    in_group_id::bigint,
    '[]'::jsonb,
    in_user_id::bigint,
    CURRENT_TIMESTAMP::timestamp without time zone,
    pn_order_id,
    'U1'::text,
    'Se creó la factura borrador.'::text
  );

  oj_info := jsonb_build_object(
    'code', 202,
    'type', 'success',
    'action', 'create_invoice',
    'message', 'Se creó la factura borrador.'
  );

  oj_data := jsonb_build_object(
    'order_id', pn_order_id,
    'move_id', pn_move_id,
    'lines_count', pn_lines_count
  );

  RETURN NEXT;

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS pt_message_text = MESSAGE_TEXT;
    oj_info := jsonb_build_object(
      'code', 402,
      'type', 'error',
      'action', 'create_invoice',
      'message', 'No se pudo crear la factura borrador.',
      'sqlstate', SQLSTATE,
      'sqlerrm', SQLERRM,
      'message_text', pt_message_text
    );
    oj_data := jsonb_build_object('order_id', pn_order_id);
    RETURN NEXT;
END;
$function$;

COMMIT;
