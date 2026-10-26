CREATE OR REPLACE FUNCTION public.fnc_con_peru_ct_25(
  in_user_id integer,
  in_group_id integer,
  ij_companies jsonb,
  it_action text,
  ij_data jsonb
)
RETURNS TABLE(oj_info jsonb, oj_data jsonb, oj_data_gby jsonb, oj_audit jsonb, oj_stat jsonb)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_search text := '';
  v_id text := '';
  v_limit integer := 100;
  v_page integer := 1;
  v_total integer := 0;
  v_filter jsonb;
BEGIN
  oj_data_gby := '[]'::jsonb;
  oj_audit := '[]'::jsonb;
  oj_stat := '[]'::jsonb;

  IF it_action = 's2' THEN
    IF jsonb_typeof(ij_data) = 'array' AND jsonb_array_length(ij_data) > 0 THEN
      IF jsonb_typeof(ij_data->0) = 'object' THEN
        v_search := TRIM(COALESCE(ij_data->0->>'search', ''));
        IF COALESCE(ij_data->0->>'limit', '') ~ '^\d+$' THEN
          v_limit := LEAST(GREATEST((ij_data->0->>'limit')::integer, 1), 100);
        END IF;
      ELSIF jsonb_typeof(ij_data->0) = 'string' THEN
        v_search := TRIM(ij_data->>0);
      END IF;
    ELSIF jsonb_typeof(ij_data) = 'object' THEN
      v_search := TRIM(COALESCE(ij_data->>'search', ''));
      IF COALESCE(ij_data->>'limit', '') ~ '^\d+$' THEN
        v_limit := LEAST(GREATEST((ij_data->>'limit')::integer, 1), 100);
      END IF;
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(result) ORDER BY result.id_producto), '[]'::jsonb)
    INTO oj_data
    FROM (
      SELECT
        c.id_producto AS value,
        c.id_producto || ' - ' || c.producto AS label,
        c.id_producto AS unspsc_code_id,
        c.id_producto,
        c.producto,
        c.id_clase,
        c.clase,
        c.familia
      FROM tbl_con_peru_ct_25 c
      WHERE c.state = 'A'
        AND (
          v_search = ''
          OR c.id_producto ILIKE v_search || '%'
          OR c.producto ILIKE '%' || v_search || '%'
          OR c.clase ILIKE '%' || v_search || '%'
        )
      ORDER BY c.id_producto
      LIMIT v_limit
    ) result;

    oj_info := fnc_config_message(200, NULL, NULL);
    RETURN NEXT;

  ELSIF it_action = 's1' THEN
    IF jsonb_typeof(ij_data) = 'array' AND jsonb_array_length(ij_data) > 0 THEN
      IF jsonb_typeof(ij_data->0) = 'array' THEN
        v_id := TRIM(COALESCE(ij_data->0->>0, ''));
      ELSIF jsonb_typeof(ij_data->0) = 'object' THEN
        v_id := TRIM(COALESCE(ij_data->0->>'id_producto', ij_data->0->>'unspsc_code_id', ''));
      ELSE
        v_id := TRIM(COALESCE(ij_data->>0, ''));
      END IF;
    ELSIF jsonb_typeof(ij_data) = 'object' THEN
      v_id := TRIM(COALESCE(ij_data->>'id_producto', ij_data->>'unspsc_code_id', ''));
    ELSE
      v_id := TRIM(COALESCE(ij_data::text, ''));
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(result)), '[]'::jsonb)
    INTO oj_data
    FROM (
      SELECT
        c.id_producto,
        c.producto,
        c.id_clase,
        c.clase,
        c.familia,
        c.id_producto AS unspsc_code_id,
        c.id_producto || ' - ' || c.producto AS cod_unspsc__dsc_unspsc,
        c.state
      FROM tbl_con_peru_ct_25 c
      WHERE c.id_producto = v_id
      LIMIT 1
    ) result;

    oj_info := fnc_config_message(200, NULL, NULL);
    RETURN NEXT;

  ELSIF it_action = 's' THEN
    IF jsonb_typeof(ij_data) = 'array' THEN
      FOR v_filter IN SELECT value FROM jsonb_array_elements(ij_data)
      LOOP
        IF jsonb_typeof(v_filter) = 'array'
          AND v_filter->>1 = 'pag'
          AND COALESCE(v_filter->>2, '') ~ '^\d+$' THEN
          v_page := GREATEST((v_filter->>2)::integer, 1);
        END IF;
      END LOOP;
    END IF;

    SELECT count(*) INTO v_total
    FROM tbl_con_peru_ct_25 c
    WHERE c.state = 'A';

    SELECT COALESCE(jsonb_agg(to_jsonb(result) ORDER BY result.id_producto), '[]'::jsonb)
    INTO oj_data
    FROM (
      SELECT
        c.id_producto,
        c.producto,
        c.id_clase,
        c.clase,
        c.familia,
        c.id_producto AS unspsc_code_id,
        c.id_producto || ' - ' || c.producto AS cod_unspsc__dsc_unspsc,
        c.state
      FROM tbl_con_peru_ct_25 c
      WHERE c.state = 'A'
      ORDER BY c.id_producto
      LIMIT 80 OFFSET (v_page - 1) * 80
    ) result;

    oj_info := fnc_config_message(200, NULL, NULL, v_total);
    RETURN NEXT;
  END IF;

  oj_info := fnc_config_message(200, NULL, NULL);
  oj_data := '[]'::jsonb;
  RETURN NEXT;
END;
$function$;
