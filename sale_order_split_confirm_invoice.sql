ALTER TABLE public.account_move_lines
ADD COLUMN IF NOT EXISTS sale_order_line_id bigint;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'account_move_lines_sale_order_line_id_fkey'
  ) THEN
    ALTER TABLE public.account_move_lines
    ADD CONSTRAINT account_move_lines_sale_order_line_id_fkey
    FOREIGN KEY (sale_order_line_id)
    REFERENCES public.sale_order_lines(line_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS account_move_lines_sale_order_line_id_idx
ON public.account_move_lines(sale_order_line_id);

CREATE OR REPLACE FUNCTION public.fnc_sale_order_audit_insert(
  in_group_id bigint,
  ij_files jsonb,
  in_user_id bigint,
  id_creation_date timestamp without time zone,
  in_order_id bigint,
  it_action_id text,
  it_content text DEFAULT NULL,
  it_edi_code text DEFAULT NULL,
  it_edi_message text DEFAULT NULL
)
RETURNS TABLE(oj_info jsonb, oj_data jsonb)
LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO public.sale_order_audit (
    group_id,
    files,
    user_id,
    creation_date,
    order_id,
    action_id,
    content,
    edi_code,
    edi_message
  )
  VALUES (
    in_group_id,
    COALESCE(ij_files, '[]'::jsonb),
    in_user_id,
    COALESCE(id_creation_date, CURRENT_TIMESTAMP),
    in_order_id,
    it_action_id,
    it_content,
    it_edi_code,
    it_edi_message
  );

  oj_info := jsonb_build_object(
    'code', 203,
    'type', 'success',
    'action', 'insert',
    'message', '¡Se realizó el registro con éxito!'
  );
  oj_data := jsonb_build_object('order_id', in_order_id);
  RETURN NEXT;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Error en fnc_sale_order_audit_insert: % %', SQLSTATE, SQLERRM;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fnc_sale_order_sync_invoiced_from_move(
  in_move_id bigint,
  in_user_id bigint,
  in_group_id bigint
)
RETURNS TABLE(oj_info jsonb, oj_data jsonb)
LANGUAGE plpgsql
AS $function$
DECLARE
  pn_updated_count integer := 0;
  pt_message_text text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.account_move am
    WHERE am.move_id = in_move_id
      AND am.group_id = in_group_id
      AND am.state = 'R'
  ) THEN
    RAISE EXCEPTION 'La factura % debe estar registrada para sincronizar venta', in_move_id;
  END IF;

  WITH affected_sale_lines AS (
    SELECT DISTINCT aml.sale_order_line_id AS line_id
    FROM public.account_move_lines aml
    INNER JOIN public.account_move am
      ON am.move_id = aml.move_id
    WHERE aml.move_id = in_move_id
      AND am.group_id = in_group_id
      AND aml.sale_order_line_id IS NOT NULL
  ),
  invoiced_by_line AS (
    SELECT
      aml.sale_order_line_id AS line_id,
      SUM(COALESCE(aml.quantity, 0)) AS invoiced_quantity
    FROM public.account_move_lines aml
    INNER JOIN public.account_move am
      ON am.move_id = aml.move_id
    WHERE am.group_id = in_group_id
      AND am.state = 'R'
      AND aml.sale_order_line_id IN (SELECT line_id FROM affected_sale_lines)
    GROUP BY aml.sale_order_line_id
  ),
  updated AS (
    UPDATE public.sale_order_lines sol
    SET
      invoiced_total = COALESCE(ibl.invoiced_quantity, 0),
      invoiced_residual = GREATEST(
        COALESCE(sol.quantity, 0) - COALESCE(ibl.invoiced_quantity, 0),
        0
      )
    FROM invoiced_by_line ibl
    WHERE sol.line_id = ibl.line_id
    RETURNING sol.line_id
  )
  SELECT count(*)
  INTO pn_updated_count
  FROM updated;

  oj_info := jsonb_build_object(
    'code', 203,
    'type', 'success',
    'action', 'sync_invoiced',
    'message', 'Cantidades facturadas sincronizadas.'
  );
  oj_data := jsonb_build_object(
    'move_id', in_move_id,
    'updated_lines', pn_updated_count
  );
  RETURN NEXT;

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS pt_message_text = MESSAGE_TEXT;
    oj_info := jsonb_build_object(
      'code', 402,
      'type', 'error',
      'action', 'sync_invoiced',
      'message', 'No se pudo sincronizar cantidades facturadas.',
      'sqlstate', SQLSTATE,
      'sqlerrm', SQLERRM,
      'message_text', pt_message_text
    );
    oj_data := jsonb_build_object('move_id', in_move_id);
    RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fnc_sale_order_confirm(
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
  pn_order_id bigint;
  pt_state text;
  pt_message_text text;
BEGIN
  pn_order_id := NULLIF(ij_data->>'order_id', '')::bigint;

  SELECT so.state
  INTO pt_state
  FROM public.sale_order so
  WHERE so.order_id = pn_order_id
    AND so.group_id = in_group_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la orden de venta % para el grupo %', pn_order_id, in_group_id;
  END IF;

  IF pt_state = 'S' THEN
    oj_info := jsonb_build_object(
      'code', 203,
      'type', 'success',
      'action', 'confirm',
      'message', 'La cotización ya estaba enviada.'
    );
    oj_data := jsonb_build_object('order_id', pn_order_id);
    RETURN NEXT;
    RETURN;
  END IF;

  IF pt_state NOT IN ('D', 'S') THEN
    RAISE EXCEPTION 'La orden de venta % no está en estado confirmable', pn_order_id;
  END IF;

  UPDATE public.sale_order
  SET
    state = 'S',
    confirmation_date = COALESCE(confirmation_date, CURRENT_TIMESTAMP),
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
    'U2'::text,
    'Cotización enviada.'::text
  );

  oj_info := jsonb_build_object(
    'code', 203,
    'type', 'success',
    'action', 'confirm',
      'message', 'Cotización enviada.'
  );
  oj_data := jsonb_build_object('order_id', pn_order_id);
  RETURN NEXT;

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS pt_message_text = MESSAGE_TEXT;
    oj_info := jsonb_build_object(
      'code', 402,
      'type', 'error',
      'action', 'confirm',
      'message', 'No se pudo confirmar la orden.',
      'sqlstate', SQLSTATE,
      'sqlerrm', SQLERRM,
      'message_text', pt_message_text
    );
    oj_data := jsonb_build_object('order_id', pn_order_id);
    RETURN NEXT;
END;
$function$;

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
  pb_has_invoice_lines :=
    COALESCE(
      jsonb_typeof(ij_data->'invoice_lines') = 'array'
      AND jsonb_array_length(ij_data->'invoice_lines') > 0,
      false
    );

  SELECT so.*
  INTO pr_order
  FROM public.sale_order so
  WHERE so.order_id = pn_order_id
    AND so.group_id = in_group_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la orden de venta % para el grupo %', pn_order_id, in_group_id;
  END IF;

  IF pr_order.state NOT IN ('S', 'R') THEN
    RAISE EXCEPTION 'La orden de venta % debe estar en cotización enviada u orden de venta para crear factura', pn_order_id;
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
      AND am.state = 'D'
  ) THEN
    RAISE EXCEPTION 'La orden de venta % ya tiene una factura borrador pendiente', pn_order_id;
  END IF;

  IF pb_has_invoice_lines AND EXISTS (
    WITH requested_lines AS (
      SELECT
        NULLIF(item->>'line_id', '')::bigint AS line_id,
        NULLIF(item->>'quantity', '')::double precision AS quantity_to_invoice
      FROM jsonb_array_elements(ij_data->'invoice_lines') item
    )
    SELECT 1
    FROM requested_lines
    WHERE line_id IS NULL
      OR quantity_to_invoice IS NULL
      OR quantity_to_invoice <= 0
  ) THEN
    RAISE EXCEPTION 'Las líneas a facturar tienen cantidades inválidas';
  END IF;

  IF pb_has_invoice_lines AND EXISTS (
    WITH requested_lines AS (
      SELECT DISTINCT NULLIF(item->>'line_id', '')::bigint AS line_id
      FROM jsonb_array_elements(ij_data->'invoice_lines') item
    )
    SELECT 1
    FROM requested_lines req
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.sale_order_lines sol
      WHERE sol.order_id = pn_order_id
        AND sol.line_id = req.line_id
    )
  ) THEN
    RAISE EXCEPTION 'Una o más líneas no pertenecen a la orden de venta %', pn_order_id;
  END IF;

  pn_journal_id := pr_order.journal_id;

  IF pn_journal_id IS NULL THEN
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
  END IF;

  IF pn_journal_id IS NULL THEN
    RAISE EXCEPTION 'No existe un diario de ventas activo para la orden %', pn_order_id;
  END IF;

  pn_document_type_id := COALESCE(pr_order.document_type_id, 1);

  INSERT INTO public.account_move (
    group_id,
    company_id,
    state,
    creation_user,
    creation_date,
    type,
    name,
    partner_id,
    invoice_date,
    date,
    invoice_date_due,
    payment_reference,
    payment_term_id,
    currency_id,
    reference,
    seller_id,
    team_id,
    bank_account_id,
    delivery_date,
    terms_and_conditions,
    amount_tax,
    amount_untaxed,
    amount_withtaxed,
    amount_residual,
    journal_id,
    document_type_id,
    document_number,
    edi_operation_id,
    edi_state,
    payment_state,
    email_sent,
    amount_payment,
    files,
    edi_sent,
    document
  )
  VALUES (
    pr_order.group_id,
    pr_order.company_id,
    'D',
    in_user_id,
    CURRENT_TIMESTAMP,
    'C',
    NULL,
    pr_order.customer_id,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    pr_order.expected_date,
    pr_order.payment_reference,
    pr_order.payment_term_id,
    pr_order.currency_id,
    pr_order.reference,
    pr_order.seller_id,
    pr_order.team_id,
    pr_order.bank_account_id,
    pr_order.delivery_date,
    pr_order.terms_and_conditions,
    0,
    0,
    0,
    0,
    pn_journal_id,
    pn_document_type_id,
    NULL,
    pr_order.edi_operation_id,
    'P',
    'PE',
    'U',
    0,
    pr_order.files,
    'U',
    'I'
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

  INSERT INTO public.account_move_taxes (
    move_id,
    tax_group_id,
    amount
  )
  SELECT
    pn_move_id,
    tx.tax_group_id,
    SUM(COALESCE(amlt.amount, 0))
  FROM public.account_move_lines aml
  INNER JOIN public.account_move_lines_taxes amlt
    ON amlt.line_id = aml.line_id
  INNER JOIN public.tax tx
    ON tx.tax_id = amlt.tax_id
  WHERE aml.move_id = pn_move_id
  GROUP BY tx.tax_group_id;

  UPDATE public.account_move
  SET
    amount_untaxed = pn_amount_untaxed,
    amount_tax = pn_amount_tax,
    amount_withtaxed = pn_amount_withtaxed,
    amount_residual = pn_amount_withtaxed,
    amount_payment = 0,
    payment_state = 'PE',
    modification_user = in_user_id,
    modification_date = CURRENT_TIMESTAMP
  WHERE move_id = pn_move_id;

  UPDATE public.sale_order
  SET
    state = 'R',
    confirmation_date = CURRENT_TIMESTAMP,
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

DO $$
DECLARE
  pt_function text;
  pt_original_function text;
BEGIN
  SELECT pg_get_functiondef('public.fnc_sale_order_confirm_create_move(bigint,bigint,bigint)'::regprocedure)
  INTO pt_function;

  pt_original_function := pt_function;

  IF position('pr_order.state NOT IN (''D'', ''S'', ''R'')' in pt_function) = 0 THEN
    pt_function := replace(
      pt_function,
      'IF pr_order.state IS DISTINCT FROM ''D'' THEN',
      'IF pr_order.state NOT IN (''D'', ''S'', ''R'') THEN'
    );
    pt_function := replace(
      pt_function,
      'IF pr_order.state NOT IN (''D'', ''R'') THEN',
      'IF pr_order.state NOT IN (''D'', ''S'', ''R'') THEN'
    );
    pt_function := replace(
      pt_function,
      'RAISE EXCEPTION ''La orden de venta % no está en estado Borrador'',',
      'RAISE EXCEPTION ''La orden de venta % debe estar en borrador o confirmada'','
    );
    pt_function := replace(
      pt_function,
      '''La orden fue confirmada y se creó el borrador de facturación.''' ,
      '''Se creó la factura borrador.'''
    );
  END IF;

  IF position('sale_order_line_id' in pt_function) = 0 THEN
    pt_function := replace(
      pt_function,
      'INSERT INTO public.account_move_lines (
            move_id,',
      'INSERT INTO public.account_move_lines (
            sale_order_line_id,
            move_id,'
    );

    pt_function := replace(
      pt_function,
      'VALUES (
            pn_move_id,',
      'VALUES (
            pr_line.line_id,
            pn_move_id,'
    );
  END IF;

  pt_function := replace(
    pt_function,
    '        UPDATE public.sale_order_lines
        SET
            invoiced_total = COALESCE(invoiced_total, 0) + pn_invoice_quantity,
            invoiced_residual = GREATEST(
                quantity - (COALESCE(invoiced_total, 0) + pn_invoice_quantity),
                0
            )
        WHERE line_id = pr_line.line_id;',
    '        -- La cantidad facturada se sincroniza al registrar la factura,
        -- no al crear el borrador.'
  );

  IF pt_function IS DISTINCT FROM pt_original_function THEN
    EXECUTE pt_function;
  END IF;
END $$;
