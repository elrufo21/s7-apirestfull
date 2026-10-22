-- Keep one canonical implementation and a non-ambiguous compatibility wrapper.
BEGIN;

CREATE OR REPLACE FUNCTION public.fnc_sale_order_update_invoiced_quantities(
  p_order_id bigint
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  v_total_items integer := 0;
  v_zero_invoiced_items integer := 0;
  v_fully_invoiced_items integer := 0;
  v_order_state varchar(30);
  v_new_invoice_state varchar(30) := 'nothing';
BEGIN
  IF p_order_id IS NULL THEN
    RETURN;
  END IF;

  SELECT state INTO v_order_state
  FROM public.sale_order
  WHERE order_id = p_order_id;

  IF v_order_state IS NULL OR v_order_state IN ('draft', 'cancel') THEN
    UPDATE public.sale_order
    SET invoice_state = 'nothing'
    WHERE order_id = p_order_id;
    RETURN;
  END IF;

  /* CÓDIGO ANTERIOR:
  -- Anteriormente solo se sumaban las cantidades cuando la factura estaba confirmada (am.state = 'posted')
  WITH invoiced_by_line AS (
    SELECT
      aml.sale_order_line_id AS line_id,
      SUM(COALESCE(aml.quantity, 0)) AS total_invoiced
    FROM public.account_move_lines aml
    INNER JOIN public.account_move am ON am.move_id = aml.move_id
    WHERE am.state = 'posted'
      AND aml.sale_order_line_id IS NOT NULL
      AND aml.sale_order_line_id IN (
        SELECT line_id
        FROM public.sale_order_lines
        WHERE order_id = p_order_id
          AND (type = 'L' OR type IS NULL OR product_id IS NOT NULL)
      )
    GROUP BY aml.sale_order_line_id
  )
  UPDATE public.sale_order_lines sol
  SET
    invoiced_total = COALESCE(ibl.total_invoiced, 0),
    invoiced_residual = GREATEST(COALESCE(sol.quantity, 0) - COALESCE(ibl.total_invoiced, 0), 0)
  FROM invoiced_by_line ibl
  WHERE sol.line_id = ibl.line_id
    AND sol.order_id = p_order_id;

  UPDATE public.sale_order_lines sol
  SET
    invoiced_total = 0,
    invoiced_residual = COALESCE(sol.quantity, 0)
  WHERE sol.order_id = p_order_id
    AND (sol.type = 'L' OR sol.type IS NULL OR sol.product_id IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1
      FROM public.account_move_lines aml
      INNER JOIN public.account_move am ON am.move_id = aml.move_id
      WHERE am.state = 'posted'
        AND aml.sale_order_line_id = sol.line_id
    );
  -- FIN CÓDIGO ANTERIOR */

  -- NUEVA IMPLEMENTACIÓN: Considerar facturas confirmadas ('posted') y en borrador ('draft'), excluyendo canceladas ('cancel')
  WITH invoiced_by_line AS (
    SELECT
      aml.sale_order_line_id AS line_id,
      SUM(COALESCE(aml.quantity, 0)) AS total_invoiced
    FROM public.account_move_lines aml
    INNER JOIN public.account_move am ON am.move_id = aml.move_id
    WHERE am.state IN ('posted', 'draft')
      AND aml.sale_order_line_id IS NOT NULL
      AND aml.sale_order_line_id IN (
        SELECT line_id
        FROM public.sale_order_lines
        WHERE order_id = p_order_id
          AND (type = 'L' OR type IS NULL OR product_id IS NOT NULL)
      )
    GROUP BY aml.sale_order_line_id
  )
  UPDATE public.sale_order_lines sol
  SET
    invoiced_total = COALESCE(ibl.total_invoiced, 0),
    invoiced_residual = GREATEST(COALESCE(sol.quantity, 0) - COALESCE(ibl.total_invoiced, 0), 0)
  FROM invoiced_by_line ibl
  WHERE sol.line_id = ibl.line_id
    AND sol.order_id = p_order_id;

  UPDATE public.sale_order_lines sol
  SET
    invoiced_total = 0,
    invoiced_residual = COALESCE(sol.quantity, 0)
  WHERE sol.order_id = p_order_id
    AND (sol.type = 'L' OR sol.type IS NULL OR sol.product_id IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1
      FROM public.account_move_lines aml
      INNER JOIN public.account_move am ON am.move_id = aml.move_id
      WHERE am.state IN ('posted', 'draft')
        AND aml.sale_order_line_id = sol.line_id
    );

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE COALESCE(invoiced_total, 0) = 0),
    COUNT(*) FILTER (
      WHERE COALESCE(invoiced_residual, 0) <= 0
        AND COALESCE(quantity, 0) > 0
    )
  INTO v_total_items, v_zero_invoiced_items, v_fully_invoiced_items
  FROM public.sale_order_lines
  WHERE order_id = p_order_id
    AND (type = 'L' OR type IS NULL OR product_id IS NOT NULL);

  IF v_total_items = 0 OR v_zero_invoiced_items = v_total_items THEN
    v_new_invoice_state := 'pending';
  ELSIF v_fully_invoiced_items = v_total_items THEN
    v_new_invoice_state := 'complete';
  ELSE
    v_new_invoice_state := 'partial';
  END IF;

  UPDATE public.sale_order
  SET invoice_state = v_new_invoice_state
  WHERE order_id = p_order_id;
END;
$function$;

-- Keep two-argument callers compatible without making one-argument calls ambiguous.
DROP FUNCTION public.fnc_sale_order_update_invoiced_quantities(bigint, bigint);

CREATE FUNCTION public.fnc_sale_order_update_invoiced_quantities(
  p_order_id bigint,
  p_user_id bigint
)
RETURNS boolean
LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM public.fnc_sale_order_update_invoiced_quantities(p_order_id);
  RETURN true;
END;
$function$;

COMMIT;
