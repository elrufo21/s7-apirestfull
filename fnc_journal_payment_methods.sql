CREATE OR REPLACE FUNCTION public.fnc_journal_payment_methods(in_user_id integer, in_group_id integer, ij_companies jsonb, it_action text, ij_data jsonb)
 RETURNS TABLE(oj_info jsonb, oj_data jsonb, oj_data_gby jsonb, oj_audit jsonb, oj_stat jsonb)
 LANGUAGE plpgsql
AS $function$
declare

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
  
  -- dynamic variables
  pt_sql text;
  a text := '''';
  pt_get_search_column text := '(fnc_config_tools(it_plot_1 => ' || a || 'get_search_column' || '|' || a || ' || @column)).ot_1';
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
  pt_s2_columns text;

  /* --------------------------------------------------------------------------------------------------
  |                                               process
  */---------------------------------------------------------------------------------------------------

  -- general variables
  pt_fnc text := 'fnc_journal_payment_methods';
  pb_grouped_list boolean := true;
  
  -- filter variables
  pt_filter_state text := '';
  pt_filter_name text := '';

  -- temporary table variables
  tmp_data text := 'data_' || pt_uuid;
  tmp_base text := 'T001_' || pt_uuid;
  tmp_base_name text := 'T002_' || pt_uuid;
  tmp_base_name_lower text := 'T003_' || pt_uuid;
  tmp_base_name_lower_filtered text := 'T004_' || pt_uuid;

  pj_table_config jsonb := '
  [
    {
    "schema": "public",
    "table": "journal_payment_methods",
    "column_id": "payment_method_id",
    "columns_copy": ["name"],
    "column_sort": "payment_method_id",
    "direction_sort": "desc",
    "s2_column_name": "name",
    "columns":
            {
            "alias":
                    [
                      {"column": "default_alias", "alias": "t1"}
                    ]
            }
    }
  ]';
  pj_columns_alias jsonb := (((pj_table_config)::jsonb->0)::jsonb->>'columns')::jsonb->>'alias';

/*
    "s2":
          {
          "schema": "",
          "table": "' || tmp_base_name || '",
              "columns":
                        [
                          {"column": "bank_account_id", "as": "bank_account_id"},
                          {"column": "number", "as": "number"},

                          {"column": "bank_account_id", "as": "value"},
                          {"column": "number", "as": "label"}
                        ]
          }
*/
begin

  if it_action = 'r' or it_action = 'd' then
    pb_list_select_all := (fnc_config_tools(it_plot_1 => 'list_select_all', ij_data => ij_data)).ob_1;
  elsif it_action = 's2' then
    pt_s2_columns := (fnc_config_tools(it_plot_1 => 's2_columns', ij_1 => pj_table_config, ij_2 => pj_columns_alias, ij_data => ij_data)).ot_1;
  end if;

  /* --------------------------------------------------------------------------------------------------
  |                                    process: temporary tables - start
  */---------------------------------------------------------------------------------------------------

  if it_action = 's' or it_action = 's1' or it_action = 's2' or pb_list_select_all = true then

    -- name - start
    pt_sql := '
    create temp table ' || tmp_base_name || ' as 
    (
      select 
        t2.*,
        pm.name,
        t1.group_id 
      from 
        public.journal t1
        inner join public.journal_payment_methods t2 on t1.journal_id = t2.journal_id
        left join public.payment_method pm on pm.payment_method_id = t2.payment_method_id
      where 
        t1.group_id = ' || in_group_id || ' 
        and t1.state = ' || a || 'A' || a || '
    );
    create index ' || tmp_base_name || '_idx_01 on ' || tmp_base_name || ' using btree (payment_method_id);
    ';
    execute pt_sql;
    -- name - end

  end if;

  /* --------------------------------------------------------------------------------------------------
  |                                    process: temporary tables - end
  */---------------------------------------------------------------------------------------------------
  
  if it_action = 's' or it_action = 's2' or pb_list_select_all = true then

    /* --------------------------------------------------------------------------------------------------
    |                                        process filters - start
    */---------------------------------------------------------------------------------------------------

    --pt_filter_state := ' and t1.state = ' || a || 'A' || a;
    pt_filter_state := '';
    for i in 0..jsonb_array_length(ij_data)-1 loop
      pj_1 := ((ij_data)::jsonb->>i)::jsonb;
      pt_config_type := pj_1->>1;
      pt_config_filter_key := '';

      if pt_config_type = 'fequal' then
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'fequal', ij_1 => pj_1, ij_2 => pj_columns_alias)).ot_1;
      elsif pt_config_type = 'finclude' then
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'finclude', ij_1 => pj_config_filter_values, ij_2 => pj_columns_alias)).ot_1;
      elsif pt_config_type = 'multi_filter_in' then
        pj_config_filter_values := pj_1->>2;
        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'multi_filter_in', ij_1 => pj_columns_alias, ij_2 => pj_config_filter_values)).ot_1;
      elsif pt_config_type = 'fcon' then
        pt_config_filter_key := pj_1->>3;
        pj_config_filter_values := (pj_1->>4)::jsonb;
      elsif pt_config_type = 'fcol' then
        pt_config_filter_key := pj_1->>3;
        pj_config_filter_values := (pj_1->>2)::jsonb;
      end if;
      
      if pt_config_filter_key = 'state' then
        --pt_filter_state := ' and t1.state = ' || a || 'I' || a;

      elsif pt_config_filter_key = 'name' then
        pj_2 := '[{"col": "name_lower"}]';
        pt_filter_name := pt_filter_name || (fnc_config_tools(it_plot_1 => 'filter_like', ij_1 => pj_config_filter_values, ij_2 => pj_2)).ot_1;

      end if;

    end loop;
    pt_config_filters := pt_filter_state || pt_config_filters_columns;

    /* --------------------------------------------------------------------------------------------------
    |                                        process filters - end
    */---------------------------------------------------------------------------------------------------
    
    if it_action = 's' or it_action = 's2' or pb_list_select_all = true then

      /* --------------------------------------------------------------------------------------------------
      |                                    process: temporary tables - start
      */---------------------------------------------------------------------------------------------------

      if length(pt_filter_name) > 0 then

        pt_sql := '
        create temp table ' || tmp_base_name_lower || ' as 
        (
          select 
            t1.*, '
            || replace(pt_get_search_column, '@column', 'name') || ' name_lower 
          from ' || tmp_base_name || ' t1
        );
        create index ' || tmp_base_name_lower || '_idx_01 on ' || tmp_base_name_lower || ' using btree (payment_term_id);
        create index ' || tmp_base_name_lower || '_idx_02 on ' || tmp_base_name_lower || ' using gin (name_lower gin_trgm_ops);
        ';
        execute pt_sql;

        pt_sql := '
        create temp table ' || tmp_base_name_lower_filtered || ' as 
        (
          select 
            t1.* 
          from ' || tmp_base_name_lower || ' t1 
          where ' || pt_filter_name || '
        );
        create index ' || tmp_base_name_lower_filtered || '_idx_01 on ' || tmp_base_name_lower_filtered || ' using btree (payment_term_id);
        ';
        execute pt_sql;

        tmp_base := tmp_base_name_lower_filtered;
      else
        tmp_base := tmp_base_name;
        --tmp_base := 'journal';
      end if;

      /* --------------------------------------------------------------------------------------------------
      |                                    process: temporary tables - end
      */---------------------------------------------------------------------------------------------------

      -- data table query - start
      pt_base_table_columns_query := '
        t1.* 
      ';

      pt_base_table_query := '
      select 
        @columns 
      from ' || 
        tmp_base || ' t1 
      where 
        t1.group_id = ' || in_group_id || ' @config_filters 
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
  when it_action = 's' or it_action = 's2' then
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

    if pb_extract_final_data = true then

      -- final data - start
      if it_action = 's' then
        /*
        pt_base_table_columns_query := '
        json_agg('
        
        -- Block 1 - start
        || 'jsonb_build_object(' || 
        (fnc_config_tools(it_plot_1 => 'query_all_columns|' || '' || '|' || tmp_data || '|' || 't1')).ot_1 
        || ') || '
        -- Block 1 - end

        -- Block 2 - start
        || 'jsonb_build_object(' || 
        (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
        '[
          ["company_name", "con_cia.name"],
          ["CASE_WHEN", "type_description", "t1.type", [["SA","Ventas"],["SH","Compras"],["CS","Efectivo"],["BK","Banco"],["CC","Tarjeta de crédito"],["MS","Misceláneo"],["SE","Misceláneo"]]]
        ]')).ot_1 
        || ') '
        -- Block 2 - end

        || ') 
        ';
        */
      elsif it_action = 's2' then
        pt_base_table_columns_query := 'json_agg(jsonb_build_object(' || pt_s2_columns || '))';
      end if;
      
      pt_sql := '
      select ' || 
        pt_base_table_columns_query || ' 
      from ' || tmp_data || ' t1';
      execute pt_sql into oj_data;
      -- final data - end

    end if;

    oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb, pn_base_table_count);

  when it_action = 's1' then
    /*
    pn_code := 200;
    pn_code_error := 400;
    pn_row_id := (((ij_data)::jsonb->>0)::jsonb->>0)::text;

    pt_sql := '
    select
      json_agg('
      
      -- block 1 - start
      || 'jsonb_build_object(' || 
      (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'journal' || '|' || 't1')).ot_1 || ', ' || 

      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
      '[
        ["company_name", "cia_con.name"],
        ["currency_name", "mon.name"]
      ]')).ot_1 
      
      || ') || '
      -- block 1 - end

      -- block 2 - start
      || 'jsonb_build_object(' 

      -- payment_methods_in - start
      || a || 'payment_methods_in' || a || ', 
      coalesce(
	    (
        select json_agg(result.*) from 
        (
          select 
            ' || a || a || ' action,
            payment_method_id,
            order_id,
            payment_type,
            payment_method_type_id,
            name
          from
            journal_payment_methods
          where
            journal_id = t1.journal_id
            and payment_type = ' || a || 'I' || a || '
        ) result
      )
      , ' || a || '[]' || a || ')'
      -- payment_methods_in - end

      -- payment_methods_out - start
      || ', ' || a || 'payment_methods_out' || a || ', 
      coalesce(
	    (
        select json_agg(result.*) from 
        (
          select 
            ' || a || a || ' action,
            payment_method_id,
            order_id,
            payment_type,
            payment_method_type_id,
            name
          from
            journal_payment_methods
          where
            journal_id = t1.journal_id
            and payment_type = ' || a || 'O' || a || '
        ) result
      )
      , ' || a || '[]' || a || ')'
      -- payment_methods_out - end

      || ')'
      -- block 2 - end

      || ') 
    from 
      public.journal t1
      left join public.currency mon on mon.currency_id = t1.currency_id

      left join company cia on cia.company_id = t1.company_id
      left join partner cia_con on cia_con.partner_id = cia.partner_id
    where 
      t1.journal_id = ' || pn_row_id;
    
    execute pt_sql into oj_data;

    oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb);
    */

  when it_action = 'i' then
    pn_code := 200;
    declare
      ln_journal_id bigint;
      ln_payment_method_id bigint;
      lt_payment_type varchar;
      ln_position bigint;
      ln_line_id bigint;
      lj_item jsonb;
    begin
      if jsonb_typeof(ij_data) = 'array' then
        lj_item := ij_data->0;
      else
        lj_item := ij_data;
      end if;

      ln_journal_id := (lj_item->>'journal_id')::bigint;
      ln_payment_method_id := (lj_item->>'payment_method_id')::bigint;
      lt_payment_type := coalesce(nullif(lj_item->>'payment_type', ''), 'I');

      if ln_journal_id is not null and ln_payment_method_id is not null then
        select line_id into ln_line_id
        from public.journal_payment_methods
        where journal_id = ln_journal_id
          and payment_method_id = ln_payment_method_id
          and payment_type = lt_payment_type
        limit 1;

        if ln_line_id is null then
          select coalesce(max(position), 0) + 1 into ln_position
          from public.journal_payment_methods
          where journal_id = ln_journal_id
            and payment_type = lt_payment_type;

          insert into public.journal_payment_methods(
            journal_id,
            payment_method_id,
            payment_type,
            position
          ) values (
            ln_journal_id,
            ln_payment_method_id,
            lt_payment_type,
            ln_position
          ) returning line_id into ln_line_id;
        end if;

        oj_data := jsonb_build_array(jsonb_build_object(
          'line_id', ln_line_id,
          'journal_id', ln_journal_id,
          'payment_method_id', ln_payment_method_id,
          'payment_type', lt_payment_type
        ));
      else
        oj_data := '[]'::jsonb;
      end if;

      oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb, 1);
    end;

  else
    oj_info := fnc_config_message(200, developer_text, developer_jsonb, 0);
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
