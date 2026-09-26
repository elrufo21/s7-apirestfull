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

CREATE OR REPLACE FUNCTION public.fnc_sale_order(in_user_id integer, in_group_id integer, ij_companies jsonb, it_action text, ij_data jsonb)
 RETURNS TABLE(oj_info jsonb, oj_data jsonb, oj_data_gby jsonb, oj_audit jsonb, oj_stat jsonb)
 LANGUAGE plpgsql
AS $function$
declare

  in_id_cia text := '';

  /* --------------------------------------------------------------------------------------------------
  |                                               function
  */---------------------------------------------------------------------------------------------------

  -- exception variables
  pt_message_text text;
  pt_constraint_name text;
  pt_pg_exception_hint text;
  pt_pg_exception_detail text;
  developer_text text;
  developer_jsonb jsonb;
  
  -- general variables
  pt_uuid text := replace(replace(extract(second from current_timestamp)::text, '.', '') || '-' || gen_random_uuid()::text, '-', '_');
  pn_code int;
  pn_code_error int;
  pn_row_id int;
  pr_fnc_result record;
  pj_1 jsonb;
  pj_2 jsonb;
  pj_columns jsonb;
  pt_type text;

  pt_1 text;
  pn_1 int;
  pn_audit_order_id bigint;
  pt_audit_action_id text;
  pt_audit_content text;

  -- dynamic variables
  pt_sql text;
  a text := '''';
  pt_config_type text;
  pt_config_filter_key text;
  pj_config_filter_values jsonb;
  pt_config_filters text := '';
  pt_config_filters_columns text := '';

  pt_base_table_query text;
  pt_base_table_columns_query text;
  pn_base_table_count int;

  pb_list_select_all boolean := false;
  pj_gby_cols jsonb;
  pn_pagination_page int;
  pb_extract_final_data boolean;
 
  /* --------------------------------------------------------------------------------------------------
  |                                               process
  */---------------------------------------------------------------------------------------------------

  -- general variables
  pt_fnc text := 'fnc_sale_order';
  pb_grouped_list boolean := true;
  
  -- filter variables
  pt_filter_state text := '';
  pt_filter_name text := '';
  pt_filter_categories text := '';

  -- temporary table variables
  tmp_data text := 'data_' || pt_uuid;
  tmp_base text := 'T001_' || pt_uuid;
  tmp_base_name text := 'T002_' || pt_uuid;
  tmp_base_name_lower text := 'T003_' || pt_uuid;  
  tmp_base_name_lower_filtered text := 'T004_' || pt_uuid;
  tmp_base_categories__ijoin__data text := 'T005_' || pt_uuid;
  tmp_category text := 'T006_' || pt_uuid;
  tmp_category_name_lower text := 'T007_' || pt_uuid;
  tmp_category_filtered text := 'T008_' || pt_uuid;
  tmp_category_filtered__join__base_categories text := 'T009_' || pt_uuid;
  pt_base_categories text;
  pt_base_categories__ijoin__data text := '';

  -- pj_table_config: define la tabla principal (sale_order) y sus tablas relacionadas.
  -- column_id en cada tabla relacionada debe ser el ID TÉCNICO real de esa tabla,
  -- porque fnc_config_tools_crud lo usa para excluirlo del INSERT.
  --   sale_order_lines        -> line_id        (correcto, PK real)
  --   sale_order_lines_taxes  -> line_tax_id     (PK real, NO tax_id)
  --   sale_order_taxes        -> order_tax_id    (PK real, NO tax_id)
  pj_table_config jsonb := '
  [
    {
    "schema": "public",
    "table": "sale_order",
    "column_id": "order_id",
    "column_name": "name",
    "column_sort": "order_id",
    "direction_sort": "desc",
    "columns":
            {
            "alias":
                    [
                      {"column": "default_alias", "alias": "ord"},

                      {"column": "full_name", "alias": "dsc_con"},
                      {"column": "location_sl1_name", "alias": "dpt"},
                      {"column": "location_country_name", "alias": "pais"},
                      {"column": "company_name", "alias": "con_cia"}
                    ],
            "exclude_update": ["edi_sent", "edi_state",  "edi_xml_request", "edi_xml_response", "edi_code", "edi_message"]
            }, 
    "related_tables": 
                    [
                      {
                      "schema": "public",
                      "table": "sale_order_lines",
                      "column_id": "line_id",
                      "in_jsonb": "order_lines",
                      "related_tables": 
                                      [
                                        {
                                        "schema": "public",
                                        "table": "sale_order_lines_taxes",
                                        "in_jsonb": "order_lines_taxes"
                                        }
                                      ]
                      },
                      {
                      "schema": "public",
                      "table": "sale_order_taxes",
                      "column_id": "order_tax_id",
                      "in_jsonb": "taxes"
                      }
                    ]
    }
  ]';
  pj_columns_alias jsonb := (((pj_table_config)::jsonb->0)::jsonb->>'columns')::jsonb->>'alias';

  -- statistics
  pn_payments int;
  pn_invoices int;

begin

  if it_action = 'r' or it_action = 'd' then
    pb_list_select_all := (fnc_config_tools(it_plot_1 => 'list_select_all', ij_data => ij_data)).ob_1;
  end if;

  /* --------------------------------------------------------------------------------------------------
  |                                    process: temporary tables - start
  |  (bloque genérico sobre "partner"; no depende de account_move ni de sale_order, se conserva igual)
  */---------------------------------------------------------------------------------------------------

  if it_action = 's_pos' or it_action = 's' or it_action = 's1' or it_action = 's2' or pb_list_select_all = true then
    
    -- partner description - start
    pt_sql := '
    create temp table ' || tmp_base_name || ' as 
    (
      select
        group_id,
        partner_id,
        state,
        type,
        nullif(base_parent_id, 0) base_parent_id, 
        full_name, 
        parent_full_name, 
        case
        when workstation <> ' || a || a || ' and workstation is not null and parent_id is not null then workstation || ' || a || ' en ' || a || ' || parent_full_name
        when workstation <> ' || a || a || ' and workstation is not null and parent_id is null then workstation 
        else parent_full_name 
        end workstation__parent_full_name, 
        
        parent_name,
        name

      from
      (
        select
          distinct on (partner_id)
          group_id,
          partner_id,
          state,
          type,
          parent_id,
          base_parent_id,
          name,
          base_name,
          address_type,
          parent_name,
          parent_address_type,
          workstation,
          depth,

          case
          when depth = 0 and name <> ' || a || a || ' then name
          when depth = 0 and name = ' || a || a || ' then ' || a || a || '
          when depth >= 1 and name <> ' || a || a || ' then base_name || ' || a || ', ' || a || '|| name
          when depth >= 1 and name = ' || a || a || ' then
            (
            case
            when address_type = ' || a ||  'DF' || a || ' then base_name || ' || a || ', ' || a || ' || ' || a || 'Dirección de facturación' || a || '
            when address_type = ' || a ||  'DE' || a || ' then base_name || ' || a || ', ' || a || ' || ' || a || 'Dirección de entrega' || a || '
            when address_type = ' || a ||  'OD' || a || ' then base_name || ' || a || ', ' || a || ' || ' || a || 'Otra dirección' || a || '
            else ' || a || 'sin codificar' || a || '
            end
            )
          else ' || a || 'sin codificar' || a || '
          end full_name,
  
          case
          when depth = 0 then ' || a || a || '
          when depth = 1 and base_name <> ' || a || a || ' then base_name
          when depth >= 2 and base_name <> ' || a || a || ' and parent_name <> ' || a || a || ' then base_name || ' || a || ', ' || a || ' || parent_name
          when depth >= 2 and base_name <> ' || a || a || ' and (parent_name = ' || a || a || ' or parent_name is null) then
            (
            case
            when parent_address_type = ' || a ||  'DF' || a || ' then base_name || ' || a || ', ' || a || ' || ' || a || 'Dirección de facturación' || a || '
            when parent_address_type = ' || a ||  'DE' || a || ' then base_name || ' || a || ', ' || a || ' || ' || a || 'Dirección de entrega' || a || '
            when parent_address_type = ' || a ||  'OD' || a || ' then base_name || ' || a || ', ' || a || ' || ' || a || 'Otra dirección' || a || '
            else ' || a || 'sin codificar' || a || '
            end
            )
          else ' || a || 'sin codificar' || a || '
          end parent_full_name 
        from
        (
        with recursive tabla__tree (group_id, partner_id, state , type, parent_id, base_parent_id, name, base_name, address_type, parent_name, parent_address_type, workstation, depth) as 
        (
          select 
            con.group_id,
            con.partner_id,
            con.state,
            con.type,
            con.parent_id,
            con.partner_id as base_parent_id,
            coalesce(con.name, ' || a || a || ') name,
            con.name as base_name,
            con.address_type, 
            rel.name parent_name, 
            rel.address_type parent_address_type, 
            con.workstation,
            0 as depth
          from
            partner con
            left join partner rel on con.parent_id = rel.partner_id
          where con.group_id = ' || in_group_id || '
          union
          select 
            t1.group_id,
            t1.partner_id,
            t1.state,
            t1.type,
            t1.parent_id,
            t.base_parent_id as base_parent_id,
            coalesce(t1.name, ' || a || a || ') name,
            t.base_name as base_name,
            t1.address_type,
            rel.name parent_name,
            rel.address_type parent_address_type,
            t1.workstation,
            t.depth + 1 as depth
          from
            partner t1
            inner join tabla__tree as t on t1.parent_id = t.partner_id
            left join partner rel on t1.parent_id = rel.partner_id
        )
          select
            con.group_id,
            con.partner_id,
            con.state,
            con.type,
            con.name,
            con.parent_id,

            case
            when con.parent_id is null then 0
            else con.base_parent_id
            end base_parent_id,

            case
            when con.parent_id is null then ' || a || a || '
            else con.base_name
            end base_name,

            address_type,
            parent_name,
            parent_address_type,
            workstation,
            depth
          from tabla__tree con
        ) tbl_result_order
        order by partner_id desc, depth desc
      ) tbl_result
    );
    --create index ' || tmp_base_name || '_idx_01 on ' || tmp_base_name || ' using btree (partner_id);
    --create index ' || tmp_base_name || '_idx_02 on ' || tmp_base_name || ' using gin (name gin_trgm_ops);
    ';
    execute pt_sql;
    -- partner description - end

  end if;

  if it_action = 's' or it_action = 's1' or pb_list_select_all = true then
    /*
    -- category - start
    pt_sql := '
    create temp table ' || tmp_category || ' as 
    (' ||
      (select * from fnc_construct_query_recursive(
      in_group_id, 
      in_id_cia, 
      'partner_category', 
      'category',
      '["state", "color"]'
      )) || '
    );
    create index ' || tmp_category || '_idx_01 on ' || tmp_category || ' using btree (category_id);
    create index ' || tmp_category || '_idx_02 on ' || tmp_category || ' using gin (full_name gin_trgm_ops);
    ';
    execute pt_sql;
    -- category - end

    -- text partner categories - start
    pt_base_categories := ', ' || a || 'categories' || a || ', 
    coalesce((
              select 
                json_agg(jsonb_build_object(' ||
                (select * from fnc_construct_query_columns(
                '[
                  ["value", "cet.category_id"],
                  ["label", "cet.name"],
                  ["category_id", "cet.category_id"],
                  ["state", "cet.state"],
                  ["name", "cet.name"],
                  ["color", "cet.color"],
                  ["parent_id", "cet.parent_id"],
                  ["full_name", "cet.full_name"]
                ]'
                )) || '
                ))
              from ' || tmp_category || ' cet 
              where 
                cet.category_id in (@partner_categories__ijoin__base)
            ), ' || a || '[]' || a || ')';
    -- text partner categories - end
    */
  end if;

  /* --------------------------------------------------------------------------------------------------
  |                                    process: temporary tables - end
  */---------------------------------------------------------------------------------------------------
  
  if it_action = 's' or pb_list_select_all = true then

    /* --------------------------------------------------------------------------------------------------
    |                                        process filters - start
    */---------------------------------------------------------------------------------------------------

    --pt_filter_state := ' and con.state = ' || a || 'A' || a;
    pt_filter_state := '';
    for i in 0..jsonb_array_length(ij_data)-1 loop
      pj_1 := ((ij_data)::jsonb->>i)::jsonb;
      pt_config_type := pj_1->>1;
      pt_config_filter_key := '';

      if pt_config_type = 'fbetween' then
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'fbetween', ij_1 => pj_1, ij_2 => pj_columns_alias)).ot_1;
      elsif pt_config_type = 'fequal' then
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'fequal', ij_1 => pj_1, ij_2 => pj_columns_alias)).ot_1;
      elsif pt_config_type = 'multi_filter_in' then
        pj_config_filter_values := pj_1->>2;
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'multi_filter_in', ij_1 => pj_columns_alias, ij_2 => pj_config_filter_values)).ot_1;
      elsif pt_config_type = 'fcon' then
        pt_config_type := pj_1->>3;
        if pt_config_type = 'date' then
          pj_config_filter_values := pj_1->>4;

          pt_1 := '';
          --pt_config_filters_columns
          pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'fdate', ij_1 => pj_columns_alias, ij_2 => pj_config_filter_values)).ot_1;

        else
          pt_config_filter_key := pj_1->>3;
          pj_config_filter_values := (pj_1->>4)::jsonb;

        end if;

      elsif pt_config_type = 'fcol' then
        pt_config_filter_key := pj_1->>3;
        pj_config_filter_values := (pj_1->>2)::jsonb;
      end if;
  
      if pt_config_filter_key = 'state' then
        --pt_filter_state := ' and ord.state = ' || a || 'R' || a;

      elsif pt_config_filter_key = 'document' or pt_config_filter_key = '2' or pt_config_filter_key = '3' then
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'multi_filter_in', ij_1 => pj_columns_alias, ij_2 => pj_config_filter_values)).ot_1;
      /*
      elsif pt_config_filter_key = 'session_name' then -- culminado
        pt_1 := '(lower(point.name) || ' || a || '/' || a || ' || lpad((session.sequence::text), 5, ' || a || '0' || a || '))';
        pj_2 := '[{"col": "' || pt_1 || '"}]';
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'filter_like|and', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = 'point_name' then -- culminado
        pj_2 := '[{"col": "point_name_lower"}]';
        pt_filter_point_name := pt_filter_point_name || (fnc_config_tools(it_plot_1 => 'filter_like', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = 'partner_name' then -- culminado
        pj_2 := '[{"col": "name_lower"}]';
        pt_filter_name := pt_filter_name || (fnc_config_tools(it_plot_1 => 'filter_like', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = 'user_name' then -- culminado
        pj_2 := '[{"col": "usu.user_name_lower"}]';
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'filter_like|and', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = 'receipt_number' then
          pj_2 := '[{"col": "ord.receipt_number"}]';
          pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'filter_like|and', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;
        
      elsif pt_config_filter_key = 'phone__mobile' then
          pj_2 := '[{"col": "con.phone"}, {"col": "con.mobile"}]';
          pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'filter_like|and', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = 'category_name' then
        pt_filter_categories := ' where ';
        pj_2 := '[{"col": "cet_tmp.full_name_lower"}]';
        pt_filter_categories := pt_filter_categories || (fnc_config_tools(it_plot_1 => 'filter_like', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = '1' then
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'multi_filter_in', ij_1 => pj_columns_alias, ij_2 => pj_config_filter_values)).ot_1;
      */
      end if;

    end loop;
    pt_config_filters := pt_filter_state || pt_config_filters_columns;
--developer_text := pt_config_filters;

    /* --------------------------------------------------------------------------------------------------
    |                                        process filters - end
    */---------------------------------------------------------------------------------------------------

    if it_action = 's' or pb_list_select_all = true then

      /* --------------------------------------------------------------------------------------------------
      |                                    process: temporary tables - start
      */---------------------------------------------------------------------------------------------------

      -- base table - start
      if length(pt_filter_categories) > 0 then
        /*
        pt_sql := '
        create temp table ' || tmp_category_name_lower || ' as 
        (
          select 
            c.*, 
            lower(full_name) full_name_lower
          from ' || tmp_category || ' c
        );
        create index ' || tmp_category_name_lower || '_idx_01 on ' || tmp_category_name_lower || ' using btree (category_id);
        create index ' || tmp_category_name_lower || '_idx_02 on ' || tmp_category_name_lower || ' using gin (full_name_lower gin_trgm_ops);
        ';
        execute pt_sql;

        pt_sql := '
        create temp table ' || tmp_category_filtered || ' as 
        (
          select 
            cet_tmp.category_id
          from ' || 
          tmp_category_name_lower || ' cet_tmp ' || 
          pt_filter_categories || '
        );
        create index ' || tmp_category_filtered || '_idx_01 on ' || tmp_category_filtered || ' using btree (category_id);
        ';
        execute pt_sql;

        pt_sql := '
        create temp table ' || tmp_category_filtered__join__base_categories || ' as 
        (
          select 
            distinct con_cet.partner_id
          from ' || 
            tmp_category_filtered || ' cet 
            inner join partner_categories con_cet on con_cet.category_id = cet.category_id 
        );
        create index ' || tmp_category_filtered__join__base_categories || '_idx_01 on ' || tmp_category_filtered__join__base_categories || ' using btree (partner_id);
        ';
        execute pt_sql;

        pt_sql := '
        create temp table ' || tmp_base || ' as 
        (
          select 
            con.* 
          from 
            partner con 
            inner join ' || tmp_category_filtered__join__base_categories || ' cet on cet.partner_id = con.partner_id 
          where 
            con.group_id = '|| in_group_id || '
        );
        create index ' || tmp_base || '_idx_01 on ' || tmp_base || ' using btree (partner_id);
        create index ' || tmp_base || '_idx_02 on ' || tmp_base || ' using gin (name gin_trgm_ops); -- validar si se usa
        ';
        execute pt_sql;
        */
      else
        tmp_base := 'sale_order';
      end if;
      -- base table - end

      if length(pt_filter_name) > 0 then
        /*
        pt_sql := '
        create temp table ' || tmp_base_name_lower || ' as 
        (
          select 
            con.*, 
            lower(name) name_lower,
            lower(parent_full_name) parent_full_name_lower
          from ' || tmp_base_name || ' con
        );
        create index ' || tmp_base_name_lower || '_idx_01 on ' || tmp_base_name_lower || ' using btree (partner_id);
        create index ' || tmp_base_name_lower || '_idx_02 on ' || tmp_base_name_lower || ' using gin (name_lower gin_trgm_ops);
        create index ' || tmp_base_name_lower || '_idx_03 on ' || tmp_base_name_lower || ' using gin (parent_full_name_lower gin_trgm_ops);
        ';
        execute pt_sql;

        pt_sql := '
        create temp table ' || tmp_base_name_lower_filtered || ' as 
        (
          select 
            con.*, 1 bool
          from ' || tmp_base_name_lower || ' con 
          where ' || pt_filter_name || '
        );
        create index ' || tmp_base_name_lower_filtered || '_idx_01 on ' || tmp_base_name_lower_filtered || ' using btree (partner_id);
        create index ' || tmp_base_name_lower_filtered || '_idx_02 on ' || tmp_base_name_lower_filtered || ' using btree (bool);
        ';
        execute pt_sql;

        tmp_base_name := tmp_base_name_lower_filtered;
        pt_config_filters := pt_config_filters || ' and dsc_con.bool is not null ';
        */
      end if;

      /* --------------------------------------------------------------------------------------------------
      |                                    process: temporary tables - end
      */---------------------------------------------------------------------------------------------------

      -- data table query - start
      pt_base_table_columns_query := '
        ord.*, 

        case 
          when ord.state = ' || a || 'D' || a || ' then ' || a || 'Borrador' || a || ' 
          when ord.state = ' || a || 'R' || a || ' then ' || a || 'Registrado' || a || ' 
          when ord.state = ' || a || 'C' || a || ' then ' || a || 'Cancelado' || a || ' 
        end state_description,

        ord.state combined_state,

        case
          when ord.state = ' || a || 'D' || a || ' then ' || a || 'Cotización' || a || '
          when ord.state = ' || a || 'S' || a || ' then ' || a || 'Cotización enviada' || a || '
          when ord.state = ' || a || 'R' || a || ' then ' || a || 'Orden de venta' || a || '
          when ord.state = ' || a || 'C' || a || ' then ' || a || 'Cancelado' || a || '
        end combined_state_description,

        dsc_con.full_name partner_name, 
        
        to_char(ord.amount_subtotal, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_subtotal_in_currency,
        to_char(ord.amount_tax, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_tax_in_currency,
        to_char(ord.amount_total, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_total_in_currency

        /*
        con_cia.name company_name, 

        dst.name location_sl3_name, 
        prv.name location_sl2_name, 
        dpt.name location_sl1_name, 
        pais.name location_country_name, 
        (prv.name || ' || a || ', ' || a || ' || pais.name) location_sl2_name__location_country_name, 

        case 
          when con.type = ' || a || 'I' || a || ' then ' || a || 'Individual' || a || ' 
          when con.type = ' || a || 'C' || a || ' then ' || a || 'Compañia' || a || ' 
        end type_description 
        */
      ';

      pt_base_table_query := '
      select 
        @columns 
      from ' || 
        tmp_base || ' ord 
        left join ' || tmp_base_name || ' dsc_con on dsc_con.partner_id = ord.customer_id 
        left join currency div on div.currency_id = ord.currency_id 

      /*
        left join location_sl3 dst on dst.location_sl3_id = con.location_sl3_id 
        left join location_sl2 prv on prv.location_sl2_id = con.location_sl2_id 
        left join location_sl1 dpt on dpt.location_sl1_id = con.location_sl1_id 
        left join location_country pais on pais.country_id = con.location_country_id 

        left join company cia on cia.company_id = con.company_id 
        left join partner con_cia on con_cia.partner_id = cia.partner_id 
      */
      
      where 
        ord.group_id = ' || in_group_id || ' @config_filters 
      @orderBy 
      @offset';
      -- data table query - end

    end if;

    if pb_list_select_all = true then
      pr_fnc_result := fnc_config(pb_list_select_all, pb_grouped_list, ij_data, pt_config_filters, tmp_data, pt_base_table_query, pt_base_table_columns_query, pj_table_config);
      ij_data := pr_fnc_result.oj_data;
    end if;

  end if;

  case
  when it_action = 's' then
    pn_code := 200;
    pn_code_error := 400;

    -- configuration values - start
    pr_fnc_result := fnc_config(pb_list_select_all, pb_grouped_list, ij_data, pt_config_filters, tmp_data, pt_base_table_query, pt_base_table_columns_query, pj_table_config);
    pn_pagination_page := pr_fnc_result.ot_pagination_page;
    pj_gby_cols := pr_fnc_result.oj_gby_cols;
    pb_extract_final_data := pr_fnc_result.ot_pb_extract_final_data;
    pn_base_table_count := pr_fnc_result.ot_base_table_count;
    oj_data_gby := pr_fnc_result.oj_data;
    -- developer_jsonb := pr_fnc_result.oj_info; -- desarrollo
    -- configuration values - end

    if jsonb_array_length(pj_gby_cols) > 0 then -- grouped list
      /*
      --if pn_pagination_page = 0 then -- grouped list: groupers
      --elsif pn_pagination_page > 0 then  -- grouped list: data
      if pn_pagination_page > 0 then  -- grouped list: data

        -- partner categories - start
        pt_base_categories__ijoin__data := '
        select 
          con_cet.category_id 
        from partner_categories con_cet 
        inner join ' || tmp_data || ' result on result.partner_id = con_cet.partner_id and result.partner_id = con.partner_id
        ';
        pt_base_categories := replace(pt_base_categories, '@partner_categories__ijoin__base', pt_base_categories__ijoin__data);
        -- partner categories - end
      
      end if;
      */
    else -- simple list
      /*
      -- table labels - start
      pt_sql := '
      create temp table ' || tmp_base_categories__ijoin__data || ' as 
      (
        select con_cet.* 
        from 
        partner_categories con_cet 
        inner join ' || tmp_data || ' result on result.partner_id = con_cet.partner_id 
      );
      create index ' || tmp_base_categories__ijoin__data || '_idx_01 on ' || tmp_base_categories__ijoin__data || ' using btree (category_id);
      create index ' || tmp_base_categories__ijoin__data || '_idx_02 on ' || tmp_base_categories__ijoin__data || ' using btree (partner_id);
      ';
      execute pt_sql;
      pt_base_categories__ijoin__data := 'select category_id from ' || tmp_base_categories__ijoin__data || ' where partner_id = con.partner_id';
      pt_base_categories := replace(pt_base_categories, '@partner_categories__ijoin__base', pt_base_categories__ijoin__data);
      -- table labels - end
      */
    end if;

    if pb_extract_final_data = true then
      pt_sql := 'select jsonb_agg(to_jsonb(ord)) from ' || tmp_data || ' ord';
      execute pt_sql into oj_data;
    end if;

    oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb, pn_base_table_count);

----------------------------------------- temporal ini
  when it_action = 's_pos' then
    pn_code := 200;
    pn_code_error := 400;
    --pn_row_id := (((ij_data)::jsonb->>0)::jsonb->>0)::text;

    /*
    pt_base_categories__ijoin__data := 'select con_cet.category_id from partner_categories con_cet where con_cet.partner_id = ' || pn_row_id;
    pt_base_categories := replace(pt_base_categories, '@partner_categories__ijoin__base', pt_base_categories__ijoin__data);
    */

    pt_sql := '
    select
      json_agg('
        
        -- block 1 - start
        || 'jsonb_build_object(' || 

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'sale_order' || '|' || 'ord')).ot_1 || ', ' || 

        (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
        '[
          ["partner_name", "dsc_con.full_name"],
          ["currency_name", "div.name"],
          ["payment_term_name", "cdp.name"]

        ]')).ot_1 

      || ') || '
      -- block 1 - end

      -- block 2 - start
      || 'jsonb_build_object(' 

      -- Lista de items: ini
      || a || 'order_lines' || a || ', ('

      || 'select json_agg(jsonb_build_object(' ||

      (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'sale_order_lines' || '|' || 'lin')).ot_1 || ', ' || 

      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
      '[
        ["action", ""],
        ["uom_name", "uom.name"],
        ["product_template_id", "pdt.product_template_id"],
        ["order_lines_taxes_change", "false"]
      ]')).ot_1 || ', ' 

      || a || 'name' || a || ', (fnc_product_get_description(pdt.product_id::int, pdt.name)), '
      || a || 'amount_subtotal_in_currency' || a || ', (div.symbol || ' || a || ' ' || a || ' || lin.amount_subtotal::text), '

      || a || 'order_lines_taxes' || a || ', (
              select json_agg(result_imps) from
              (
                select
                t1.line_tax_id, t1.tax_id, t2.name as label
                from sale_order_lines_taxes t1
                inner join tax t2 on t1.tax_id = t2.tax_id
                where
                t1.line_id = lin.line_id
              ) result_imps
            )

      )
      order by lin.sequence asc
      ) 
      from 
        sale_order_lines lin 
        left join product pdt on pdt.product_id = lin.product_id 
        left join uom uom on uom.uom_id = lin.uom_id 
      where 
        lin.order_id = ord.order_id 
      )'
      -- Lista de items: fin

      || ')'
      -- block 2 - end

      || ') 
    from 
      sale_order ord 
      left join ' || tmp_base_name || ' dsc_con on dsc_con.partner_id = ord.customer_id 
      left join currency div on div.currency_id = ord.currency_id 
      left join payment_term cdp on cdp.payment_term_id = ord.payment_term_id
    ';

    execute pt_sql into oj_data;
    
    oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb);
----------------------------------------- temporal fin
  when it_action = 's1' then
    pn_code := 201;
    pn_code_error := 401;
    pn_row_id := (((ij_data)::jsonb->>0)::jsonb->>0)::text;

    /*
    pt_base_categories__ijoin__data := 'select con_cet.category_id from partner_categories con_cet where con_cet.partner_id = ' || pn_row_id;
    pt_base_categories := replace(pt_base_categories, '@partner_categories__ijoin__base', pt_base_categories__ijoin__data);
    */

    -- statistics: start
    --pn_payments := (select count(1) from public.payment_sale_order where order_id = pn_row_id);
    pn_payments := 0;
    pn_invoices := (
      select count(distinct move.move_id)
      from public.account_move move
      inner join public.account_move_lines aml on aml.move_id = move.move_id
      inner join public.sale_order_lines sol on sol.line_id = aml.sale_order_line_id
      where sol.order_id = pn_row_id
        and move.group_id = in_group_id
        and move.type in ('out_invoice', 'C')
    );
    -- statistics: end

    -- data: start
    pt_sql := '
    select
      json_agg('
        
        -- block 1A - start: columnas reales de sale_order
        -- Se separa del objeto de campos adicionales para no superar el límite
        -- de 100 argumentos de jsonb_build_object.
        || 'jsonb_build_object(' || 
          (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'sale_order' || '|' || 'ord')).ot_1
        || ') || '
        -- block 1A - end

        -- block 1B - start: campos relacionados y calculados
        || 'jsonb_build_object(' ||
          (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
          '[
            ["partner_name", "dsc_con.full_name"],
            ["currency_name", "div.name"],
            ["payment_term_name", "cdp.name"]
          ]')).ot_1 

        -- display_name: texto visual, separado del valor real almacenado en name
        || ', ' || a || 'display_name' || a || ', (
        case
        when ord.name <> ' || a || a || ' and ord.state = ' || a || 'D' || a || ' then ' || a || 'Borrador de pedido ' || a || ' || ord.name
        when (ord.name = ' || a || a || ' or ord.name is null) and ord.state = ' || a || 'D' || a || ' then ' || a || 'Borrador' || a || '
        when ord.name <> ' || a || a || ' and ord.name is not null then ord.name
        when ord.state = ' || a || 'S' || a || ' then ' || a || 'Cotización enviada #' || a || ' || ord.order_id
        when ord.state = ' || a || 'R' || a || ' then ' || a || 'Orden de venta #' || a || ' || ord.order_id
        when ord.state = ' || a || 'C' || a || ' then ' || a || 'Orden cancelada #' || a || ' || ord.order_id
        else ' || a || 'Orden #' || a || ' || ord.order_id
        end
        )'

        || ', ' || a || 'stat_payments' || a || ', ' || pn_payments::text

        || ', ' || a || 'payments' || a || ', ('

        || 'select json_agg(jsonb_build_object(' ||

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'payment' || '|' || 'p', ij_1 => '["amount"]')).ot_1 || ', ' || 

        (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
        '[
          ["amount", "m.amount"]
        ]')).ot_1 || ' 

        )
        ) 
        from 
          public.payment_sale_order m
          inner join public.payment p on (m.payment_id = p.payment_id)
        where 
          m.order_id = ord.order_id 
        )'

        || ', ' || a || 'stat_invoices' || a || ', ' || pn_invoices::text

        || ', ' || a || 'invoices' || a || ', (
        select json_agg(jsonb_build_object(
          ' || a || 'move_id' || a || ', inv.move_id,
          ' || a || 'name' || a || ', inv.name,
          ' || a || 'state' || a || ', inv.state,
          ' || a || 'amount_withtaxed' || a || ', inv.amount_withtaxed
        ) order by inv.move_id desc)
        from (
          select distinct
            move.move_id,
            move.name,
            move.state,
            move.amount_withtaxed
          from public.account_move move
          inner join public.account_move_lines aml on aml.move_id = move.move_id
          inner join public.sale_order_lines sol on sol.line_id = aml.sale_order_line_id
          where sol.order_id = ord.order_id
            and move.group_id = ord.group_id
            and move.type in (' || a || 'out_invoice' || a || ', ' || a || 'C' || a || ')
        ) inv
        )'

      || ') || '
      -- block 1B - end

      -- block additional - start
      || 'jsonb_build_object(' 

      || a || 'combined_state' || a || ', ord.state'

      || ', ' || a || 'combined_state_description' || a || ', (
      case
        when ord.state = ' || a || 'D' || a || ' then ' || a || 'Cotización' || a || '
        when ord.state = ' || a || 'S' || a || ' then ' || a || 'Cotización enviada' || a || '
        when ord.state = ' || a || 'R' || a || ' then ' || a || 'Orden de venta' || a || '
        when ord.state = ' || a || 'C' || a || ' then ' || a || 'Cancelado' || a || '
      end
      )'

      || ') || '
      -- block additional - end

      -- block 2 - start
      || 'jsonb_build_object(' 

      -- taxes_purchase - start

      -- Lista de items: ini
      || a || 'order_lines' || a || ', ('

      || 'select json_agg(jsonb_build_object(' ||

      (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'sale_order_lines' || '|' || 'lin')).ot_1 || ', ' || 

      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
      '[
        ["action", ""],
        ["uom_name", "uom.name"],
        ["product_template_id", "pdt.product_template_id"],
        ["order_lines_taxes_change", "false"]
      ]')).ot_1 || ', ' 

      || a || 'name' || a || ', (fnc_product_get_description(pdt.product_id::int, pdt.name)), '
      || a || 'amount_total_total_in_currency' || a || ', to_char(amount_total_total, ' || a || 'FM999G999G990D00' || a || '), '

      || a || 'order_lines_taxes' || a || ', (
              select json_agg(result_imps) from
              (
                select
                  t1.line_tax_id,
                  t1.tax_id, 
                  t1.tax_id value, 
                  t2.name as label,

                  t1.percentage,
                  t1.amount,
                  t2.tax_group_id,
                  t3.name tax_group_name

                from
                  public.sale_order_lines_taxes t1
                  inner join public.tax t2 on t1.tax_id = t2.tax_id
                  inner join public.tax_group t3 on t2.tax_group_id = t3.tax_group_id
                where
                  t1.line_id = lin.line_id
              ) result_imps
            )

      )
      order by lin.sequence asc
      ) 
      from 
        sale_order_lines lin 
        left join product pdt on pdt.product_id = lin.product_id 
        left join uom uom on uom.uom_id = lin.uom_id 
      where 
        lin.order_id = ord.order_id 
      )'
      -- Lista de items: fin

      -- taxes: start
      -- Impuestos generales: ahora también se une con public.tax (tx) para traer el impuesto REAL
      -- seleccionado (nombre, porcentaje, si el precio lo incluye o no), y no solo el grupo general.
      || ', ' || a || 'taxes' || a || ', ('

      || 'select json_agg(jsonb_build_object(' ||

      (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'sale_order_taxes' || '|' || 'tax')).ot_1 || ', ' || 

      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
      '[
        ["tax_name", "tx.name"],
        ["percentage", "tx.percentage"],
        ["price_include", "tx.price_include"],
        ["tax_group_name", "gtax.name"]
      ]')).ot_1 || ' 

      )
      --order by lin.order_id asc
      ) 
      from 
        public.sale_order_taxes tax
        inner join public.tax tx on tx.tax_id = tax.tax_id 
        inner join public.tax_group gtax on gtax.tax_group_id = tx.tax_group_id 
        
      where 
        tax.order_id = ord.order_id 
      )'
      -- taxes: end

----------------------------------------------------------------------- ini

      -- Lista de items: ini
      || ', ' || a || 'audit' || a || ', 
      (' || 
        'select json_agg(jsonb_build_object(' ||

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'sale_order_audit' || '|' || 'aud')).ot_1 || ', ' || 

        (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
        '[
          ["type", "act.type"],
          ["action", "act.action"],
          ["description", "act.description"],
          ["user_name", "con.name"],
          ["user_files", "con.files"]
          
        ]')).ot_1 ||

        '
        )
        order by aud.creation_date asc
        ) 
        from 
          public.sale_order_audit aud 
          inner join public.audit_action act on aud.action_id = act.action_id 

          inner join public."user" usu on aud.user_id = usu.user_id 
          inner join public.partner con on usu.partner_id = con.partner_id 
        where 
          aud.order_id = ord.order_id 
      )'
      -- Lista de items: fin

----------------------------------------------------------------------- fin

      || ')'
      -- block 2 - end

      || ') 
    from 
      sale_order ord 
      left join ' || tmp_base_name || ' dsc_con on dsc_con.partner_id = ord.customer_id 
      left join currency div on div.currency_id = ord.currency_id 
      left join payment_term cdp on cdp.payment_term_id = ord.payment_term_id

    where 
      ord.order_id = ' || pn_row_id;
    execute pt_sql into oj_data;
    -- data: end

    -- statistics: start
    oj_stat := jsonb_build_object
    (
      'invoices', pn_invoices
    );
    -- statistics: end
    
    oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb);

 when 
   it_action = 'i' or it_action = 'u' or it_action = 'd' or it_action = 'r' 
	or it_action = 'sa' or it_action = 'sd' or it_action = 'us' or it_action = 'us2'
	then
	
	    if it_action = 'i' or it_action = 'u' then
	      ij_data := jsonb_set(
	        ij_data,
	        '{order_lines}',
	        coalesce(
	          (
	            select jsonb_agg(
	              case
	                when coalesce(line->>'action', '') <> 'd' then
	                  line || jsonb_build_object(
	                    'invoiced_total',
	                    coalesce(nullif(line->>'invoiced_total', '')::double precision, 0),
	                    'invoiced_residual',
	                    greatest(
	                      coalesce(nullif(line->>'quantity', '')::double precision, 0) -
	                      coalesce(nullif(line->>'invoiced_total', '')::double precision, 0),
	                      0
	                    )
	                  )
	                else
	                  line
	              end
	            )
	            from jsonb_array_elements(
	              coalesce(ij_data->'order_lines', '[]'::jsonb)
	            ) as t(line)
	          ),
	          '[]'::jsonb
	        ),
	        true
	      );
	    end if;
	
	    pr_fnc_result := fnc_config_tools_crud
	    (
	      it_plot_1 => 'execute_process' || '|' || it_action || '|' || in_user_id || '|' || in_group_id || '|' || pt_uuid || '|' || pt_fnc, 
	      ij_1 => ij_companies,
	      ij_2 => pj_table_config,
	      ij_data => ij_data
	    );
	
	    oj_info := pr_fnc_result.oj_info;
	    oj_data := pr_fnc_result.oj_data;

      if lower(coalesce(oj_info->>'type', '')) = 'success' and it_action <> 'd' then
        pn_audit_order_id := coalesce(
          nullif(oj_data->>'order_id', '')::bigint,
          nullif(ij_data->>'order_id', '')::bigint,
          nullif(ij_data->>'sale_id', '')::bigint
        );

        pt_audit_action_id := case
          when it_action = 'i' then 'I1'
          else 'U1'
        end;

        pt_audit_content := case
          when it_action = 'i' then 'Orden creada.'
          else 'Orden actualizada.'
        end;

        if pn_audit_order_id is not null then
          update public.sale_order ord
          set billing_state = (
            select
              case
                when coalesce(sum(sol.quantity), 0) = 0 then 'N'
                when coalesce(sum(sol.invoiced_total), 0) = 0 then 'P'
                when coalesce(sum(sol.invoiced_residual), 0) = 0 then 'F'
                else 'E'
              end
            from public.sale_order_lines sol
            where sol.order_id = ord.order_id
          )
          where ord.order_id = pn_audit_order_id
            and ord.state = 'R';

          perform *
          from public.fnc_sale_order_audit_insert(
            in_group_id::bigint,
            '[]'::jsonb,
            in_user_id::bigint,
            current_timestamp::timestamp without time zone,
            pn_audit_order_id,
            pt_audit_action_id::text,
            pt_audit_content::text
          );
        end if;
      end if;
	end case;
  return next;
exception
  when others then
    get stacked diagnostics pt_message_text = MESSAGE_TEXT,
                            pt_constraint_name = CONSTRAINT_NAME,
                            pt_pg_exception_hint = PG_EXCEPTION_HINT,
                            pt_pg_exception_detail = PG_EXCEPTION_DETAIL;
    oj_data := null;
    -- developer_text := 'exception'; -- desarrollo
    oj_info := fnc_config_message
    (
      pn_code_error,
      developer_text,
      developer_jsonb,
      null,
      pt_fnc,
      sqlstate,
      sqlerrm,
      pt_message_text,
      pt_constraint_name,
      pt_pg_exception_hint,
      pt_pg_exception_detail
    );
    return next;
  end;
$function$
