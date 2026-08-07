CREATE OR REPLACE FUNCTION public.fnc_account_move(in_user_id integer, in_group_id integer, ij_companies jsonb, it_action text, ij_data jsonb)
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
  pt_fnc text := 'fnc_account_move';
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

  pj_table_config jsonb := '
  [
    {
    "schema": "public",
    "table": "account_move",
    "column_id": "move_id",
    "column_name": "name",
    "column_sort": "move_id",
    "direction_sort": "desc",
    "columns":
            {
            "alias":
                    [
                      {"column": "default_alias", "alias": "move"},

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
                      "table": "account_move_lines",
                      "column_id": "line_id",
                      "in_jsonb": "move_lines",
                      "related_tables": 
                                      [
                                        {
                                        "schema": "public",
                                        "table": "account_move_lines_taxes",
                                        "in_jsonb": "move_lines_taxes"
                                        }
                                      ]
                      },
                      {
                      "schema": "public",
                      "table": "account_move_taxes",
                      "column_id": "tax_id",
                      "in_jsonb": "taxes"
                      }
                    ]
    }
  ]';
  pj_columns_alias jsonb := (((pj_table_config)::jsonb->0)::jsonb->>'columns')::jsonb->>'alias';

  -- statistics
  pn_payments int;

begin

  if it_action = 'r' or it_action = 'd' then
    pb_list_select_all := (fnc_config_tools(it_plot_1 => 'list_select_all', ij_data => ij_data)).ob_1;
  end if;

  /* --------------------------------------------------------------------------------------------------
  |                                    process: temporary tables - start
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
        --pt_filter_state := ' and move.state = ' || a || 'R' || a;

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
          pj_2 := '[{"col": "move.receipt_number"}]';
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
----------------------------------------------------------------------
/*
    --pt_filter_state := ' and con.state = ' || a || 'A' || a;
    pt_filter_state := '';
    for i in 0..jsonb_array_length(ij_data)-1 loop
      pj_1 := ((ij_data)::jsonb->>i)::jsonb;
      pt_config_type := pj_1->>1;
      pt_config_filter_key := '';

      if pt_config_type = 'fequal' then
        pt_config_filters_columns := (fnc_config_tools(it_plot_1 => 'fequal', ij_1 => pj_1, ij_2 => pj_columns_alias)).ot_1;
      elsif pt_config_type = 'finclude' then
        pt_config_filters_columns := (fnc_config_tools(it_plot_1 => 'finclude', ij_1 => pj_config_filter_values, ij_2 => pj_columns_alias)).ot_1;
      elsif pt_config_type = 'fcon' then
        pt_config_filter_key := pj_1->>3;
        pj_config_filter_values := (pj_1->>4)::jsonb;
      elsif pt_config_type = 'fcol' then
        pt_config_filter_key := pj_1->>3;
        pj_config_filter_values := (pj_1->>2)::jsonb;
      end if;
      
      if pt_config_filter_key = 'state' then
        pt_filter_state := ' and con.state = ' || a || 'I' || a;

      elsif pt_config_filter_key = 'name' then
        pj_2 := '[{"col": "name_lower"}]';
        pt_filter_name := pt_filter_name || (fnc_config_tools(it_plot_1 => 'filter_like', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = 'parent_name' then
        pj_2 := '[{"col": "parent_full_name_lower"}, {"col": "name_lower"}]';
        pt_filter_name := pt_filter_name || (fnc_config_tools(it_plot_1 => 'filter_like', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      elsif pt_config_filter_key = 'email' then
          pj_2 := '[{"col": "con.email"}]';
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

      end if;

    end loop;
    pt_config_filters := pt_filter_state || pt_config_filters_columns;
developer_text := pt_config_filters;
*/
    /* --------------------------------------------------------------------------------------------------
    |                                        process filters - end
    */---------------------------------------------------------------------------------------------------

    if it_action = 's' or pb_list_select_all = true then

      /* --------------------------------------------------------------------------------------------------
      |                                    process: temporary tables - start
      */---------------------------------------------------------------------------------------------------

      -- partner - start
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
        tmp_base := 'account_move';
      end if;
      -- partner - end

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
        move.*, 

        case 
          when move.state = ' || a || 'D' || a || ' then ' || a || 'Borrador' || a || ' 
          when move.state = ' || a || 'R' || a || ' then ' || a || 'Registrado' || a || ' 
          when move.state = ' || a || 'C' || a || ' then ' || a || 'Cancelado' || a || ' 
        end state_description,

        (move.state || coalesce(move.payment_state,' || a || a || ')) combined_state,

        case 
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'DPE' || a || ' then ' || a || 'Borrador' || a || ' 
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'DPP' || a || ' then ' || a || 'Pago parcial' || a || ' 
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'DPF' || a || ' then ' || a || 'Pagado' || a || ' 
          
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'RPE' || a || ' then ' || a || 'Pago pendiente' || a || ' 
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'RPP' || a || ' then ' || a || 'Pago parcial' || a || ' 
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'RPF' || a || ' then ' || a || 'Pagado' || a || ' 

          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'CPE' || a || ' then ' || a || 'Cancelado' || a || ' 
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'CPP' || a || ' then ' || a || 'Cancelado' || a || ' 
          when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'CPF' || a || ' then ' || a || 'Cancelado' || a || ' 
        end combined_state_description,

        dsc_con.full_name partner_name, 
        
        to_char(move.amount_untaxed, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_untaxed_in_currency,
        to_char(move.amount_tax, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_tax_in_currency,
        to_char(move.amount_withtaxed, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_withtaxed_in_currency,
        to_char(move.amount_payment, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_payment_in_currency,
        to_char(move.amount_residual, ' || a || '"' || a || ' || ' || 'div.symbol' || ' || ' || a || '" FM999G999G990D00' || a || ') amount_residual_in_currency

        /*
        (div.symbol || ' || a || ' ' || a || ' || move.amount_untaxed::text) amount_untaxed_in_currency,
        (div.symbol || ' || a || ' ' || a || ' || move.amount_tax::text) amount_tax_in_currency,
        (div.symbol || ' || a || ' ' || a || ' || move.amount_withtaxed::text) amount_withtaxed_currency,
        (div.symbol || ' || a || ' ' || a || ' || move.amount_payment::text) amount_payment_in_currency,
        (div.symbol || ' || a || ' ' || a || ' || move.amount_residual::text) amount_residual_in_currency
        */

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
        tmp_base || ' move 
        left join ' || tmp_base_name || ' dsc_con on dsc_con.partner_id = move.partner_id 
        left join currency div on div.currency_id = move.currency_id 

      /*
        left join location_sl3 dst on dst.location_sl3_id = con.location_sl3_id 
        left join location_sl2 prv on prv.location_sl2_id = con.location_sl2_id 
        left join location_sl1 dpt on dpt.location_sl1_id = con.location_sl1_id 
        left join location_country pais on pais.country_id = con.location_country_id 

        left join company cia on cia.company_id = con.company_id 
        left join partner con_cia on con_cia.partner_id = cia.partner_id 
      */
      
      where 
        move.group_id = ' || in_group_id || ' @config_filters 
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

      -- final data - start
      pt_sql := '
      select
        json_agg('
        
        -- block 1 - start
        || 'jsonb_build_object(' || 

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || '' || '|' || tmp_data || '|' || 'move', ij_1 => '["combined_state","combined_state_description"]')).ot_1 
      
        || ') || '
        -- Block 1 - end

        -- block 2 - start
        || 'jsonb_build_object(' || 

        (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
        '[
          ["combined_state", "move.combined_state"],
          ["combined_state_description", "move.combined_state_description"]
        ]')).ot_1 
      
        || ') || '
        -- Block 2 - end

        -- Block 3 - start
        || 'jsonb_build_object(' || 
        (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
        '[
          ["CASE_WHEN", "edi_sent_description", "edi_sent", [["U","No enviado"],["S","Enviado"]]],
          ["CASE_WHEN", "edi_state_description", "edi_state", [["P","Pendiente"],["E","Error"],["S","Éxito"]]],
          ["CASE_WHEN", "payment_state_description", "payment_state", [["N","Sin pagar"],["I","En proceso"],["R","Pago parcial"],["P","Pagado"]]],
          ["CASE_WHEN", "email_sent_description", "email_sent", [["U","Sin enviar"],["S","Enviado"]]]
        ]')).ot_1 
        || ') '
        -- Block 3 - end

        || ') 
      from ' || tmp_data || ' move';
      execute pt_sql into oj_data;
      -- final data - end
    
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

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'account_move' || '|' || 'move')).ot_1 || ', ' || 

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
      || a || 'move_lines' || a || ', ('

      || 'select json_agg(jsonb_build_object(' ||

      (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'account_move_lines' || '|' || 'lin')).ot_1 || ', ' || 

      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
      '[
        ["action", ""],
        ["uom_name", "uom.name"],
        ["product_template_id", "pdt.product_template_id"],
        ["move_lines_taxes_change", "false"]
      ]')).ot_1 || ', ' 

      || a || 'name' || a || ', (fnc_product_get_description(pdt.product_id::int, pdt.name)), '
      || a || 'amount_untaxed_in_currency' || a || ', (div.symbol || ' || a || ' ' || a || ' || lin.amount_untaxed::text), '

      || a || 'move_lines_taxes' || a || ', (
              select json_agg(result_imps) from
              (
                select
                t1.tax_id, t2.name as label
                from account_move_lines_taxes t1
                inner join tax t2 on t1.tax_id = t2.tax_id
                where
                t1.line_id = lin.line_id
              ) result_imps
            )

      )
      order by lin.order_id asc
      ) 
      from 
        account_move_lines lin 
        left join product pdt on pdt.product_id = lin.product_id 
        left join uom uom on uom.uom_id = lin.uom_id 
      where 
        lin.move_id = move.move_id 
      )'
      -- Lista de items: fin

      || ')'
      -- block 2 - end

      || ') 
    from 
      account_move move 
      left join ' || tmp_base_name || ' dsc_con on dsc_con.partner_id = move.partner_id 
      left join currency div on div.currency_id = move.currency_id 
      left join payment_term cdp on cdp.payment_term_id = move.payment_term_id
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
    --pn_payments := (select count(1) from public.payment where move_id = pn_row_id);
    pn_payments := 0;
    -- statistics: end

    -- data: start
    pt_sql := '
    select
      json_agg('
        
        -- block 1 - start
        || 'jsonb_build_object(' || 
          (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'account_move' || '|' || 'move', ij_1 => '["name"]')).ot_1 || ', ' || 
          (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
          '[
            ["partner_name", "dsc_con.full_name"],
            ["currency_name", "div.name"],
            ["payment_term_name", "cdp.name"],
            ["journal_name", "jou.name"]
          ]')).ot_1 
        || ', ' || a || 'document_type_name' || a || ', (' || a || '(' || a || ' || doc.code || ' || a ||  ') ' || a || ' || doc.name)'
        || ', ' || a || 'c51_name' || a || ', (' || a || '[' || a || ' || ele.code || ' || a || '] ' || a || ' || ele.description)'

        || ', ' || a || 'name' || a || ', (
        case
        when move.name <> ' || a || a || ' and move.state = ' || a || 'D' || a || ' then ' || a || 'Borrador de factura ' || a || ' || move.name
        when (move.name = ' || a || a || ' or move.name is null) and move.state = ' || a || 'D' || a || ' then ' || a || 'Borrador' || a || '
        else move.name
        end
        )'

        -- statistics: start
        || ', ' || a || 'stat_payments' || a || ', ' || pn_payments::text --Creo que no se usa
        -- statistics: end

        -- taxes: start
        || ', ' || a || 'payments' || a || ', ('

        || 'select json_agg(jsonb_build_object(' ||

       -- (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'payment' || '|' || 'p')).ot_1 || ', ' || 

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'payment' || '|' || 'p', ij_1 => '["amount"]')).ot_1 || ', ' || 

        (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
        '[
          ["amount", "m.amount"]
        ]')).ot_1 || ' 

        )
        --order by lin.order_id asc
        ) 
        from 
          public.payment_account_move m
          inner join public.payment p on (m.payment_id = p.payment_id)
        where 
          m.move_id = move.move_id 
        )'
        -- taxes: end

      || ') || '
      -- block 1 - end

      -- block additional - start
      || 'jsonb_build_object(' 

      || a || 'combined_state' || a || ', (move.state || coalesce(move.payment_state,' || a || a || '))'

      || ', ' || a || 'combined_state_description' || a || ', (
      case 
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'DPE' || a || ' then ' || a || 'Borrador' || a || ' 
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'DPP' || a || ' then ' || a || 'Pago parcial' || a || ' 
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'DPF' || a || ' then ' || a || 'Pagado' || a || ' 
        
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'RPE' || a || ' then ' || a || 'Pago pendiente' || a || ' 
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'RPP' || a || ' then ' || a || 'Pago parcial' || a || ' 
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'RPF' || a || ' then ' || a || 'Pagado' || a || ' 

        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'CPE' || a || ' then ' || a || 'Cancelado' || a || ' 
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'CPP' || a || ' then ' || a || 'Cancelado' || a || ' 
        when move.state || coalesce(move.payment_state,' || a || a || ') = ' || a || 'CPF' || a || ' then ' || a || 'Cancelado' || a || ' 
      end 
      )'

      || ', ' || a || 'residual_payments' || a || ', (
      case 
        when move.payment_state = ' || a || 'PE' || a || ' or move.payment_state = ' || a || 'PP' || a || 'then ' 
        || '(' ||

        'select json_agg(jsonb_build_object(' ||

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'payment' || '|' || 'p')).ot_1 
        
        || ',' || a || 'amount_residual_in_currency' || a || ', (div.symbol || ' || a || ' ' || a || ' || p.amount_residual::text)' || 

        ' 
        )
        --order by lin.order_id asc
        ) 
        from 
        public.payment p
        inner join currency div on div.currency_id = p.currency_id
        where 
          p.partner_id = move.partner_id 
          and p.amount_residual > 0
        )' 
      || ' 
      else
        null
      end
      )'

      || ') || '
      -- block additional - end

      -- block 2 - start
      || 'jsonb_build_object(' 

      -- taxes_purchase - start

      -- Lista de items: ini
      || a || 'move_lines' || a || ', ('

      || 'select json_agg(jsonb_build_object(' ||

      (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'account_move_lines' || '|' || 'lin')).ot_1 || ', ' || 

      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
      '[
        ["action", ""],
        ["uom_name", "uom.name"],
        ["product_template_id", "pdt.product_template_id"],
        ["move_lines_taxes_change", "false"]
      ]')).ot_1 || ', ' 

      || a || 'name' || a || ', (fnc_product_get_description(pdt.product_id::int, pdt.name)), '
      || a || 'amount_withtaxed_total_in_currency' || a || ', to_char(amount_withtaxed_total, ' || a || 'FM999G999G990D00' || a || '), '

      || a || 'move_lines_taxes' || a || ', (
              select json_agg(result_imps) from
              (
                select
                  t1.tax_id, 
                  t1.tax_id value, 
                  t2.name as label,

                  t1.percentage,
                  t1.amount,
                  t2.tax_group_id,
                  t3.name tax_group_name

                from
                  public.account_move_lines_taxes t1
                  inner join public.tax t2 on t1.tax_id = t2.tax_id
                  inner join public.tax_group t3 on t2.tax_group_id = t3.tax_group_id
                where
                  t1.line_id = lin.line_id
              ) result_imps
            )

      )
      order by lin.order_id asc
      ) 
      from 
        account_move_lines lin 
        left join product pdt on pdt.product_id = lin.product_id 
        left join uom uom on uom.uom_id = lin.uom_id 
      where 
        lin.move_id = move.move_id 
      )'
      -- Lista de items: fin

      -- taxes: start
      || ', ' || a || 'taxes' || a || ', ('

      || 'select json_agg(jsonb_build_object(' ||

      (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'account_move_taxes' || '|' || 'tax')).ot_1 || ', ' || 

      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
      '[
        ["tax_group_name", "gtax.name"]
      ]')).ot_1 || ' 

      )
      --order by lin.order_id asc
      ) 
      from 
        public.account_move_taxes tax
        inner join public.tax_group gtax on gtax.tax_group_id = tax.tax_group_id 
        
      where 
        tax.move_id = move.move_id 
      )'
      -- taxes: end

----------------------------------------------------------------------- ini

      -- Lista de items: ini
      || ', ' || a || 'audit' || a || ', 
      (' || 
        'select json_agg(jsonb_build_object(' ||

        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'account_move_audit' || '|' || 'aud')).ot_1 || ', ' || 

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
          public.account_move_audit aud 
          inner join public.audit_action act on aud.action_id = act.action_id 

          inner join public."user" usu on aud.user_id = usu.user_id 
          inner join public.partner con on usu.partner_id = con.partner_id 
        where 
          aud.move_id = move.move_id 
      )'
      -- Lista de items: fin

----------------------------------------------------------------------- fin





      || ')'
      -- block 2 - end

      || ') 
    from 
      account_move move 
      left join ' || tmp_base_name || ' dsc_con on dsc_con.partner_id = move.partner_id 
      left join currency div on div.currency_id = move.currency_id 
      left join payment_term cdp on cdp.payment_term_id = move.payment_term_id

      left join public.journal jou on jou.journal_id = move.journal_id
      left join public.document_type doc on doc.document_type_id = move.document_type_id
      left join public.electronic_catalog_lines ele on (ele.line_id = move.edi_operation_id and ele.catalog_code = ' || a || '51' || a || ')

    where 
      move.move_id = ' || pn_row_id;
    execute pt_sql into oj_data;
    -- data: end

    /*
    -- statistics: start
    pn_payments := (select count(1) from public.payment where move_id = pn_row_id);
    oj_stat := jsonb_build_object
    (
      'payments', pn_payments
    );
    -- statistics: end
    */
    
    oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb);

  when 
     it_action = 'i' or it_action= 'u' or it_action = 'd' or it_action= 'r' 
  or it_action = 'sa' or it_action = 'sd' or it_action = 'us' or it_action = 'us2'
  then

    pr_fnc_result := fnc_config_tools_crud
    (
      it_plot_1 => 'execute_process' || '|' || it_action || '|' || in_user_id || '|' || in_group_id || '|' || pt_uuid || '|' || pt_fnc, 
      ij_1 => ij_companies,
      ij_2 => pj_table_config,
      ij_data => ij_data
    );
    oj_info := pr_fnc_result.oj_info;
    oj_data := pr_fnc_result.oj_data;

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
