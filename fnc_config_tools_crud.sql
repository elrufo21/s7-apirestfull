CREATE OR REPLACE FUNCTION public.fnc_config_tools_crud(it_plot_1 text DEFAULT NULL::text, ij_data jsonb DEFAULT NULL::jsonb, it_1 text DEFAULT NULL::text, it_2 text DEFAULT NULL::text, it_3 text DEFAULT NULL::text, ij_1 jsonb DEFAULT NULL::jsonb, ij_2 jsonb DEFAULT NULL::jsonb, ij_3 jsonb DEFAULT NULL::jsonb)
 RETURNS TABLE(on_code integer, oj_info jsonb, oj_data jsonb, oj_1 jsonb, ot_1 text, ob_1 boolean)
 LANGUAGE plpgsql
AS $function$
declare

  -- exception variables
  pt_message_text text;
  pt_constraint_name text;
  pt_pg_exception_hint text;
  pt_pg_exception_detail text;
  developer_text text;
  developer_jsonb jsonb;
  
  -- general variables
  pt_case text := split_part(it_plot_1, '|' , 1);
  pt_fnc text := 'fnc_config_tools_crud - ' || pt_case;
  --pn_code int;
  pn_code_error int;

  -- function variables
  query text;
  full_query text := '';
  a text := '''';
  a1 text := '?#7#3#@';

  pj_1 jsonb;
  pj_2 jsonb;
  pj_3 jsonb;
  pj_4 jsonb;
  
  pt_1 text;
  pt_2 text;
  pt_3 text;
  
  pr_response record;
  
  pj_sql_N1 jsonb;
  pj_sql_N2 jsonb;
  pj_sql_N3 jsonb;

  pt_sql text;
  pn_position int;
  pn_count int;

  pt_action text;
  pt_row_action text;
  
  pt_N1_action text;
  pt_N2_action text;
  pt_N3_action text;

  pn_user_id int;
  pn_group_id int;
  pt_uuid text := replace(replace(extract(second from current_timestamp)::text, '.', '') || '-' || gen_random_uuid()::text, '-', '_');

  pt_schema text;
  pt_table text;
  pt_column_id text;
  pt_column_name text;

  pj_result jsonb;
  pn_result int;

  pt_column_id_N1 text;
  pt_column_id_N2 text;
  pt_column_id_N3 text;

 
  --pt_N2_reference_id text;
 

  pt_table_N1 text;
  pt_table_N2 text;
  pt_table_N3 text;
  
  pt_key text;

  pt_main_schema text;
  pt_main_table text;
  --pt_main_column_id text;
  --pn_main_column_id_value int;
  
  --pt_related_table text;
  --pt_related_column_id text;

  pt_column text;
  pt_value text;
  pt_values text;

  pj_companies jsonb;

  -- execute_insert_rows
  pj_table_config jsonb;
  pj_table_config_new__ITEM jsonb;
  
  pt_in_jsonb text;
  pj_related_tables jsonb;
  pj_columns jsonb;
  pj_columns_copy jsonb;

  pj_related_tables_N2 jsonb;
  pj_related_tables_N3 jsonb;
  
  pj_equivalent jsonb;
  pj_excluded jsonb;

  pj_line_data jsonb;
  pj_line_data_N3 jsonb;

  pj_data_N2 jsonb;
  pj_data_N3 jsonb;
  
  -- execute_insert_rows_detail
  pt_udt_name text;
  pt_insert_columns text;
  pt_insert_values text;
  pt_column_excluded text;
  pb_column_excluded boolean;
  --pb_block_sql boolean;

  -- execute_update_rows_detail
  pt_update_set text;
  pt_update_where text;

  pt_data_change text;

  pb_equal_tables boolean;

  pn_level int;
  pn_max_level int;

  pt_N1 text;
  pt_N2 text;
  pt_N3 text;

  pb_1 boolean;

  pt_old_value text;
  pt_new_value text;

  pb_execute_insert_row_detail boolean;
  pb_execute_update_row_detail boolean;
  pb_execute_delete_row_detail boolean;

  pb_group_id boolean;

  pb_change boolean;
begin

  if pt_case = 'get_column_type' then
    on_code := 200;
    pn_code_error := 400;

    pt_schema := split_part(it_plot_1, '|' , 2);
    pt_table := split_part(it_plot_1, '|' , 3);
    pt_column := split_part(it_plot_1, '|' , 4);
    
    begin
      select
        udt_name into pt_udt_name 
      from
        information_schema.columns 
      where 
        table_schema = pt_schema and table_name = pt_table and column_name = pt_column;
    exception
    when no_data_found then
      pt_udt_name := '';
    end;

    ot_1 := pt_udt_name;

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  elsif pt_case = 'update_array' then
    on_code := 200;
    pn_code_error := 400;

    pt_old_value := split_part(it_plot_1, '|' , 2);
    pt_new_value := split_part(it_plot_1, '|' , 3);
    pj_sql_N2 := ij_1;
    
    pj_3 := '[]';
    for i in 0..jsonb_array_length(pj_sql_N2) - 1 loop
      pj_1 := ((pj_sql_N2)::jsonb->i);
      pt_key := (pj_1->>0);
      pt_sql := (pj_1->>1);
      pt_sql := replace(pt_sql, pt_old_value, pt_new_value);
      pj_2 := '[[' || '"' || pt_key || '"' || ',' || '"' || pt_sql || '"'  || ']]';
      pj_3 := pj_3 || pj_2;
    end loop;
    oj_1 := pj_3;

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  elsif pt_case = 'select_array' then
    on_code := 200;
    pn_code_error := 400;
    
    ot_1 := '';
    for i in 0..jsonb_array_length(ij_1) - 1 loop
      pj_1 := ((ij_1)::jsonb->i);
      pt_key := (pj_1->>0);
      pt_sql := (pj_1->>1);
      ot_1 := ot_1 || pt_sql;
    end loop;

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  -- execute
  elsif pt_case = 'execute_process' then

    pt_action := split_part(it_plot_1, '|', 2);
    pn_user_id := split_part(it_plot_1, '|', 3);
    pn_group_id := split_part(it_plot_1, '|', 4);
    pt_uuid := split_part(it_plot_1, '|', 5);
    pt_fnc := split_part(it_plot_1, '|', 6);
    pj_companies := ij_1;
    pj_table_config := ij_2;
    --ij_data = ij_data
--developer_text := 'pruebas';
    -- main table
    pj_1 := ((pj_table_config)::jsonb->0);
    pt_schema := (pj_1->>'schema')::text;
    pt_table := (pj_1->>'table')::text;
    pt_column_id := (pj_1->>'column_id')::text;
    pt_column_name := (pj_1->>'column_name')::text;
    pj_related_tables := (pj_1->>'related_tables')::jsonb;
    pj_columns_copy := coalesce((pj_1->>'columns_copy')::jsonb, '[]');

    if pt_action = 'i' or pt_action = 'u' then

      if pt_action = 'i' then
        on_code := 202;
        pn_code_error := 402;
      elsif pt_action = 'u' then
        on_code := 203;
        pn_code_error := 403;
      end if;

      pt_table_N1 := '';
      pt_table_N2 := '';
      pt_table_N3 := '';
      pt_column_id_N1 := '';
      pt_column_id_N2 := '';
      pt_column_id_N3 := '';
      pt_N1 := '';
      pt_N2 := '';
      pt_N3 := '';

      pj_sql_N1 := '[]';
      pj_sql_N2 := '[]';
      pj_sql_N3 := '[]';
--revision
      --pt_1 := '';
      -- level 1: get levels - start
      for n1 in 0..jsonb_array_length(pj_table_config) - 1 loop
        pj_1 := ((pj_table_config)::jsonb->n1);
        pj_related_tables_N2 := coalesce(pj_1->>'related_tables', '[]');
        pn_max_level := 1;
        
        -- level 2 - start
        for n2 in 0..jsonb_array_length(pj_related_tables_N2) - 1 loop
          pj_2 := ((pj_related_tables_N2)::jsonb->n2);
          pj_related_tables_N3 := coalesce(pj_2->>'related_tables', '[]');
          pt_in_jsonb := coalesce((pj_2->>'in_jsonb')::text, '');
          pj_data_N2 := coalesce(ij_data->>(pt_in_jsonb), '[]');

          -- a prueba
          if jsonb_array_length(pj_data_N2) > 0 and pn_max_level < 2 then
            pn_max_level := 2;
          end if;

          -- level 2 data - start
          for n2_data in 0..jsonb_array_length(pj_data_N2) - 1 loop
            pj_line_data := pj_data_N2::jsonb->n2_data;

            -- level 3 - start
            for n3 in 0..jsonb_array_length(pj_related_tables_N3) - 1 loop
              pj_3 := ((pj_related_tables_N3)::jsonb->n3);
              pt_in_jsonb := coalesce((pj_3->>'in_jsonb')::text, '');
              pj_data_N3 := coalesce(pj_line_data->>(pt_in_jsonb), '[]');

              -- revision: bloque agregado
              pb_1 := false;
              

              -- level 3 - start
              for n3_data in 0..jsonb_array_length(pj_data_N3) - 1 loop
                pj_line_data_N3 := pj_data_N3::jsonb->n3_data;
                --pt_action := coalesce(pj_line_data_N3->>('action'), 'null');
                pt_1 := coalesce(pj_line_data_N3->>('action'), 'null');
                if pt_1 <> 'null' then
                  pb_1 := true;
                end if;
              end loop;
              -- level 3 - end

              pt_1 := pt_in_jsonb || '_change';
              -- level 2 - start
              for n2_data in 0..jsonb_array_length(pj_data_N2) - 1 loop
                pj_line_data_N3 := pj_data_N2::jsonb->n2_data;
                pb_change := coalesce(pj_line_data_N3->>(pt_1), '');
                if pb_change = true then
                  pb_1 := true;
                end if;
              end loop;
              -- level 2 - end

              -- revision: cambio a prueba
              --if jsonb_array_length(pj_data_N3) > 0 and pn_max_level < 3 then
              if pb_1 = true and pn_max_level < 3 then
                pn_max_level := 3;
              end if;

            end loop;
            -- level 3 - end

          end loop;
          -- level 2 data - end

        end loop;
        -- level 2 - end
      
      end loop;
      -- level 1: get levels - end

developer_text := pn_max_level::text;
--developer_text := pb_change::text;

      -- level 1: get scripts - start
      for n1 in 0..jsonb_array_length(pj_table_config) - 1 loop

        pj_1 := ((pj_table_config)::jsonb->n1);
        pt_table_N1 := (pj_1->>'table')::text;
        pt_column_id_N1 := coalesce((pj_1->>'column_id')::text, '');
        pj_related_tables_N2 := coalesce(pj_1->>'related_tables', '[]');
        pn_level := 1;
        pt_N1 := 'N1_' || (n1+1)::text;
        pt_N2 := '';
        pt_N3 := '';

        pt_N1_action := pt_action;
        pt_N2_action := '';
        pt_N3_action := '';

        pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_insert_or_update_rows'
        || '|' || pt_action 
        || '|' || pn_user_id 
        || '|' || pn_group_id 
        || '|' || pt_column_id_N1 
        || '|' || pt_column_id_N2 
        || '|' || pt_column_id_N3 
        || '|' || pn_max_level 
        || '|' || pn_level 
        || '|' || pt_N1 
        || '|' || pt_N2 
        || '|' || pt_N3

        || '|' || pt_N1_action
        || '|' || pt_N2_action
        || '|' || pt_N3_action

        --|| '|' || pt_N2_reference_id

        || '|' || 'null'
        || '|' || 'false'
        , ij_data => jsonb_build_array(ij_data), ij_2 => pj_1);
        --oj_info := pr_response.oj_info;
        --oj_data := pr_response.oj_data;
        --developer_jsonb := pr_response.oj_info; -- desarrollo
        pj_sql_N1 := pj_sql_N1 || pr_response.oj_1;
        
        --pt_row_parent_action := pt_action;

        -- level 2 - start
        pb_equal_tables := false;
        for n2 in 0..jsonb_array_length(pj_related_tables_N2) - 1 loop
          pj_2 := ((pj_related_tables_N2)::jsonb->n2);
          pt_table_N2 := (pj_2->>'table')::text;
          pt_column_id_N2 := coalesce((pj_2->>'column_id')::text, '');
          pj_related_tables_N3 := coalesce(pj_2->>'related_tables', '[]');
          pt_in_jsonb := coalesce((pj_2->>'in_jsonb')::text, '');
          pj_data_N2 := coalesce(ij_data->>(pt_in_jsonb), '[]');

          pt_schema := (pj_2->>'schema')::text;
          pt_table := (pj_2->>'table')::text;
          pt_data_change := coalesce(ij_data->>(pt_in_jsonb || '_change')::text, 'null');
          if pt_action = 'u' and pt_data_change = 'true' then
            pt_sql := 'delete from ' || pt_schema || '.' || pt_table || ' where ' || pt_column_id_N1 || '=' || a1 || pt_N1 || '; ';
            pj_1 := '[[' || '"' || 'DEL' || '"' || ',' || '"' || pt_sql || '"'  || ']]';
            pj_sql_N2 := pj_sql_N2 || pj_1;
          end if;

          if pt_data_change = 'null' or pt_data_change = 'true' then -- Ultimo cambio 18_Marzo
          -- level 2 data - start
          for n2_data in 0..jsonb_array_length(pj_data_N2) - 1 loop
            pj_line_data := pj_data_N2::jsonb->n2_data;
            pn_level := 2;
            pt_N2 := 'N2_' || (n2_data+1)::text;
            pt_N3 := '';
            
            pt_N2_action := coalesce(pj_line_data->>('action'), 'null');

            if pt_table_N1 = pt_table_N2 then
              pb_equal_tables := true;
            end if;

            pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_insert_or_update_rows' 
            || '|' || pt_action 
            || '|' || pn_user_id 
            || '|' || pn_group_id 
            || '|' || pt_column_id_N1 
            || '|' || pt_column_id_N2 
            || '|' || pt_column_id_N3 
            || '|' || pn_max_level 
            || '|' || pn_level 
            || '|' || pt_N1 
            || '|' || pt_N2 
            || '|' || pt_N3

            || '|' || pt_N1_action
            || '|' || pt_N2_action
            || '|' || pt_N3_action

            --|| '|' || pt_N2_reference_id

            || '|' || pt_data_change
            || '|' || pb_equal_tables::text
            , ij_data => jsonb_build_array(pj_line_data), ij_2 => pj_2);
            --oj_info := pr_response.oj_info;
            --oj_data := pr_response.oj_data;
            pj_sql_N2 := pj_sql_N2 || pr_response.oj_1;

            -- level 3 - start
            pb_equal_tables := false;
            for n3 in 0..jsonb_array_length(pj_related_tables_N3) - 1 loop
              pj_3 := ((pj_related_tables_N3)::jsonb->n3);
              pt_table_N3 := (pj_3->>'table')::text;
              pt_column_id_N3 := coalesce((pj_3->>'column_id')::text, '');
              pt_in_jsonb := coalesce((pj_3->>'in_jsonb')::text, '');
              pj_data_N3 := coalesce(pj_line_data->>(pt_in_jsonb), '[]');

              pt_schema := (pj_3->>'schema')::text;
              pt_table := (pj_3->>'table')::text;
              pt_1 := coalesce(pj_line_data->>(pt_in_jsonb || '_change')::text, 'null'); -- ultimo 3 cambios
              /*
              if pt_action = 'u' and pt_1 = 'true' then
                if pt_column_id_N2 = '' then
                  pt_sql := 'delete from ' || pt_schema || '.' || pt_table || ' where ' || pt_column_id_N1 || '=' || a1 || pt_N1;
                  if pt_N2_reference_id <> '' then
                    pt_sql := pt_sql || ' and ' || pt_N2_reference_id || '=' || a1 || pt_N2;
                  end if;
                  pt_sql := pt_sql || '; ';
                else
                  pt_sql := 'delete from ' || pt_schema || '.' || pt_table || ' where ' || pt_column_id_N2 || '=' || a1 || pt_N2 || '; ';
                end if;
                
                pj_1 := '[[' || '"' || 'DEL' || '"' || ',' || '"' || pt_sql || '"'  || ']]';
                pj_sql_N3 := pj_sql_N3 || pj_1;
              end if;
              */

              if pt_action = 'u' and pt_1 = 'true' then
                if pt_column_id_N2 <> '' then
                  pt_sql := 'delete from ' || pt_schema || '.' || pt_table || ' where ' || pt_column_id_N2 || '=' || a1 || pt_N2 || '; ';
                  pj_1 := '[[' || '"' || 'DEL' || '"' || ',' || '"' || pt_sql || '"'  || ']]';
                  pj_sql_N3 := pj_sql_N3 || pj_1;
                end if;
              end if;

              -- level 3 data - start
              for n3_data in 0..jsonb_array_length(pj_data_N3) - 1 loop
                pj_line_data := pj_data_N3::jsonb->n3_data;
                pn_level := 3;
                pt_N3 := 'N3_' || (n3_data+1)::text;

                pt_N3_action := coalesce(pj_line_data->>('action'), 'null');

--developer_text := pt_table;
--developer_jsonb := pj_line_data;

                --pt_action := coalesce(pj_line_data->>('action'), 'i');
                /*
                pt_action := pj_line_data->>('action');
                if pt_action is null then
                  --developer_text := 'null';
                  pt_action := 'i';
                --else
                  --developer_text := 'action';
                end if;
                */

                if pt_table_N2 = pt_table_N3 then
                  pb_equal_tables := true;
                end if;

                pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_insert_or_update_rows' 
                || '|' || pt_action 
                || '|' || pn_user_id 
                || '|' || pn_group_id 
                || '|' || pt_column_id_N1 
                || '|' || pt_column_id_N2 
                || '|' || pt_column_id_N3 
                || '|' || pn_max_level 
                || '|' || pn_level 
                || '|' || pt_N1 
                || '|' || pt_N2 
                || '|' || pt_N3

                || '|' || pt_N1_action
                || '|' || pt_N2_action
                || '|' || pt_N3_action

                --|| '|' || pt_N2_reference_id

                || '|' || pt_1
                || '|' || pb_equal_tables::text
                , ij_data => jsonb_build_array(pj_line_data), ij_2 => pj_3);
                --developer_jsonb := pr_response.oj_info; -- solo desarrollo
                --oj_data := pr_response.oj_data;
                pj_sql_N3 := pj_sql_N3 || pr_response.oj_1;
              end loop;
              -- level 3 data - end

            end loop;
            -- level 3 - end
            
          end loop;
          -- level 2 data - end

          end if; -- Ultimo cambio 18_Marzo

        end loop;
        -- level 2 - end
      
      end loop;
      -- level 1: get scripts - end

--developer_text := pt_table_N1 || pt_table_N2 || pt_table_N3;
--developer_jsonb := pj_sql_N2;
developer_jsonb := pj_sql_N1 || pj_sql_N2 || pj_sql_N3;
--developer_jsonb := pj_sql_N3;
--developer_jsonb := pj_line_data;
      -- execute scripts - start
      for n1 in 0..jsonb_array_length(pj_sql_N1) - 1 loop
        pj_1 := ((pj_sql_N1)::jsonb->n1);
        pt_key := (pj_1->>0);
        pt_sql := (pj_1->>1);
        
        pj_3 := coalesce((pj_1->>2), '[]');
        if jsonb_array_length(pj_3) > 0 then
          pt_1 := pj_3::text;
          pt_sql := replace(pt_sql, (a1 || '_jsonb') , pt_1);
        end if;

        if pn_max_level >= 1 then
          execute pt_sql into oj_data, pn_result;

          pt_old_value := (pt_key);
          pt_new_value := pn_result;
          pj_sql_N2 := (fnc_config_tools_crud(it_plot_1 => 'update_array' || '|' || pt_old_value || '|' || pt_new_value, ij_1 => pj_sql_N2)).oj_1;
          pj_sql_N3 := (fnc_config_tools_crud(it_plot_1 => 'update_array' || '|' || pt_old_value || '|' || pt_new_value, ij_1 => pj_sql_N3)).oj_1;

          for n2 in 0..jsonb_array_length(pj_sql_N2) - 1 loop
            pj_2 := ((pj_sql_N2)::jsonb->n2);
            pt_key := (pj_2->>0);
            pt_sql := (pj_2->>1);

            if pn_max_level = 1 or pn_max_level = 2 then
              execute pt_sql;
            elsif pn_max_level > 2 then
              select position(' returning ' in pt_sql) into pn_position;
              if pn_position = 0 then
                execute pt_sql;
              else
                execute pt_sql into pj_result, pn_result;
              end if;
              
              pt_old_value := (pt_key);
              pt_new_value := pn_result;
              pj_sql_N3 := (fnc_config_tools_crud(it_plot_1 => 'update_array' || '|' || pt_old_value || '|' || pt_new_value, ij_1 => pj_sql_N3)).oj_1;
            end if;

          end loop;

          if pn_max_level = 3 then
            pt_sql := (fnc_config_tools_crud(it_plot_1 => 'select_array', ij_1 => pj_sql_N3)).ot_1;
            if pt_sql <> '' then
              execute pt_sql;
            end if;
          end if;

        end if;

      end loop;
      -- execute scripts - end

      oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

    elsif pt_action = 's2' then

      pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_s2' || '|' || pn_group_id, ij_data => ij_data, ij_1 => pj_table_config);
      oj_info := pr_response.oj_info;
      oj_data := pr_response.oj_data;

    elsif pt_action = 'sa' or pt_action = 'sd' or pt_action = 'us' or pt_action = 'us2' then

      pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_update_rows_state' || '|' || pt_action || '|' || pt_schema || '|' || pt_table || '|' || pt_column_id, ij_data => ij_data);
      oj_info := pr_response.oj_info;
      oj_data := pr_response.oj_data;

    elsif pt_action= 'r' then

      pr_response := fnc_config_rows_copy(pn_user_id, pn_group_id, pj_companies, pt_uuid, 1, pt_fnc, pt_schema, pt_table, pt_column_id, pt_column_name, ij_data, pj_related_tables, pj_columns_copy);

      oj_info := pr_response.oj_info;
      oj_data := pr_response.oj_data;

    elsif pt_action = 'd' then

      pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_delete_rows' || '|' || pt_schema || '|' || pt_table || '|' || pt_column_id, ij_data => ij_data);
      oj_info := pr_response.oj_info;
      oj_data := pr_response.oj_data;

    end if;

  elsif pt_case = 'execute_insert_or_update_rows' then
    on_code := 200;
    pn_code_error := 400;

    pb_execute_insert_row_detail := false;
    pb_execute_update_row_detail := false;
    pb_execute_delete_row_detail := false;

    pt_action := split_part(it_plot_1, '|', 2);
    pn_user_id := split_part(it_plot_1, '|', 3);
    pn_group_id := split_part(it_plot_1, '|', 4);
    
    pt_column_id_N1 := split_part(it_plot_1, '|', 5);
    pt_column_id_N2 := split_part(it_plot_1, '|', 6);
    pt_column_id_N3 := split_part(it_plot_1, '|', 7);

    pn_max_level := split_part(it_plot_1, '|', 8);
    pn_level := split_part(it_plot_1, '|', 9);
    pt_N1 := split_part(it_plot_1, '|', 10);
    pt_N2 := split_part(it_plot_1, '|', 11);
    pt_N3 := split_part(it_plot_1, '|', 12);

    pt_N1_action := split_part(it_plot_1, '|', 13);
    pt_N2_action := split_part(it_plot_1, '|', 14);
    pt_N3_action := split_part(it_plot_1, '|', 15);

    --pt_N2_reference_id := split_part(it_plot_1, '|', 16);

    pt_data_change := split_part(it_plot_1, '|', 16);
    pb_equal_tables := split_part(it_plot_1, '|', 17);

    pj_line_data := ij_data::jsonb->0;
    pj_table_config_new__ITEM := ij_2;

    pt_schema := (pj_table_config_new__ITEM->>'schema')::text;
    pt_table := (pj_table_config_new__ITEM->>'table')::text;
    
    pj_columns := coalesce((pj_table_config_new__ITEM->>'columns')::jsonb, '[]');
    pj_equivalent := coalesce((pj_columns->>'equivalent')::jsonb, '[]');
    
    if pt_action = 'i' then
      pj_excluded := coalesce((pj_columns->>'exclude_insert')::jsonb, '[]');
    elsif pt_action = 'u' then
      pj_excluded := coalesce((pj_columns->>'exclude_update')::jsonb, '[]');
    end if;

    pt_row_action := '';

    if pn_level = 3 then
      --developer_text := pt_N1_action || pt_N2_action || pt_N3_action || pt_data_change;

      if pt_N1_action = 'i' and pt_N2_action = 'i' and pt_N3_action = 'null' and pt_data_change in ('true', 'false', 'null') then
        pb_execute_insert_row_detail := true;

      elsif pt_N1_action = 'i' and pt_N2_action = 'null' and pt_N3_action = 'null' and pt_data_change in ('true', 'null') then
        pb_execute_insert_row_detail := true;
        
      elsif pt_N1_action = 'u' and pt_N2_action = 'null' and pt_N3_action = 'null' and pt_data_change in ('true', 'null') then
        pb_execute_insert_row_detail := true;

      elsif pt_N1_action = 'u' and pt_N2_action = 'null' and pt_N3_action = 'null' and pt_data_change in ('true', 'false', 'null') then
        pb_execute_insert_row_detail := true;

      elsif pt_N1_action = 'u' and pt_N2_action = 'i' and pt_N3_action = 'null' and pt_data_change in ('true', 'false', 'null') then
        pb_execute_insert_row_detail := true;

      elsif pt_N1_action = 'u' and pt_N2_action = 'u' and pt_N3_action = 'null' and pt_data_change in ('true', 'null') then
        pb_execute_insert_row_detail := true;

      --elsif pt_N1_action = 'u' and pt_N2_action = 'u' and pt_N3_action = 'null' and pt_data_change = 'true' then
      --  pb_execute_insert_row_detail := true;
      
      end if;

    else

      if pt_action = 'i' then
        pb_execute_insert_row_detail := true;

      elsif pt_action = 'u' then
        if pn_level = 1 then
          pb_execute_update_row_detail := true;

        --elsif pn_level = 2 and pt_data_change = 'null' then
        elsif (pn_level = 2 or pn_level = 3) and pt_data_change = 'null' then
          pt_row_action := (pj_line_data->>'action')::text;

          if pt_row_action = 'i' then
            pb_execute_insert_row_detail := true;
          elsif pt_row_action = 'u' then
            pb_execute_update_row_detail := true;
          elsif pt_row_action = 'd' then
            pb_execute_delete_row_detail := true;
          end if;
          
        --elsif pn_level = 2 and pt_data_change = 'true' then
        elsif (pn_level = 2 or pn_level = 3) and pt_data_change = 'true' then
          pb_execute_insert_row_detail := true;

        end if;

      end if;
    
    end if;

--developer_text := 'pt_row_action';
--developer_jsonb := pj_line_data;
    oj_1 := '[]';
    if pb_execute_insert_row_detail = true then
      pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_insert_row_detail' 
      || '|' || 'i' 
      || '|' || pn_user_id 
      || '|' || pn_group_id 
      || '|' || pt_schema 
      || '|' || pt_table 
      || '|' || pt_column_id_N1 
      || '|' || pt_column_id_N2 
      || '|' || pt_column_id_N3 
      || '|' || pn_max_level 
      || '|' || pn_level 
      || '|' || pt_N1 
      || '|' || pt_N2 
      || '|' || pt_N3 

      --|| '|' || pt_N2_reference_id 

      || '|' || pb_equal_tables::text 
      , ij_data => pj_line_data, ij_1 => pj_equivalent, ij_2 => pj_excluded);
      --oj_info := pr_response.oj_info;
      --oj_data := pr_response.oj_data;
      --developer_jsonb := pr_response.oj_info; -- desarrollo
      --developer_text := 'punto'; -- desarrollo
      oj_1 := pr_response.oj_1;

    elsif pb_execute_update_row_detail = true then
      pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_update_row_detail' 
      || '|' || 'i' 
      || '|' || pn_user_id 
      || '|' || pn_group_id 
      || '|' || pt_schema 
      || '|' || pt_table 
      || '|' || pt_column_id_N1 
      || '|' || pt_column_id_N2 
      || '|' || pt_column_id_N3 
      || '|' || pn_max_level 
      || '|' || pn_level 
      || '|' || pt_N1 
      || '|' || pt_N2 
      || '|' || pt_N3 

      --|| '|' || pt_N2_reference_id 

      , ij_data => pj_line_data, ij_1 => pj_equivalent, ij_2 => pj_excluded);
      --oj_info := pr_response.oj_info;
      --oj_data := pr_response.oj_data;
      oj_1 := pr_response.oj_1;

    elsif pb_execute_delete_row_detail = true then
      pr_response := fnc_config_tools_crud(it_plot_1 => 'execute_delete_row_detail' 
      || '|' || 'i' 
      || '|' || pn_user_id 
      || '|' || pn_group_id 
      || '|' || pt_schema 
      || '|' || pt_table 
      || '|' || pt_column_id_N1 
      || '|' || pt_column_id_N2 
      || '|' || pt_column_id_N3 
      || '|' || pn_max_level 
      || '|' || pn_level 
      || '|' || pt_N1 
      || '|' || pt_N2 
      || '|' || pt_N3 
      , ij_data => pj_line_data, ij_1 => pj_equivalent, ij_2 => pj_excluded);
      --oj_info := pr_response.oj_info;
      --oj_data := pr_response.oj_data;
      oj_1 := pr_response.oj_1;
    end if;
    
    --developer_text := pt_table;
    --developer_jsonb := pj_related_tables;
    --oj_info := jsonb_build_object('developer_jsonb', developer_jsonb, 'developer_text', developer_text); -- desarrollo
    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb); -- produccion

  elsif pt_case = 'execute_delete_row_detail' then
    on_code := 200;
    pn_code_error := 400;

    pj_4 := '[]';
    oj_1 := '[]';

    pt_action := split_part(it_plot_1, '|' , 2);
    pn_user_id := split_part(it_plot_1, '|' , 3);
    pn_group_id := split_part(it_plot_1, '|' , 4);
    pt_schema := split_part(it_plot_1, '|' , 5);
    pt_table := split_part(it_plot_1, '|' , 6);
    
    pt_column_id_N1 := split_part(it_plot_1, '|', 7);
    pt_column_id_N2 := split_part(it_plot_1, '|', 8);
    pt_column_id_N3 := split_part(it_plot_1, '|', 9);
    
    pn_max_level := split_part(it_plot_1, '|', 10);
    pn_level := split_part(it_plot_1, '|', 11);
    pt_N1 := split_part(it_plot_1, '|', 12);
    pt_N2 := split_part(it_plot_1, '|', 13);
    pt_N3 := split_part(it_plot_1, '|', 14);

    --ij_data jsonb,
    pj_equivalent := ij_1;
    pj_excluded := ij_2;

    if pn_level = 1 then
      pt_column_id := pt_column_id_N1;
    elsif pn_level = 2 then
      pt_column_id := pt_column_id_N2;
    elsif pn_level = 3 then
      pt_column_id := pt_column_id_N3;
    end if;

    -- sql - start
    pj_1 := ij_data;
    pj_2 := (select json_agg(t) from (select jsonb_object_keys(pj_1) as column) t)::jsonb;

    --pt_update_set := '';
    pt_update_where := '';

    for j in 0..jsonb_array_length(pj_2) - 1 loop
      pj_3 := (pj_2)::jsonb->j;
      pt_column := (pj_3->>'column')::text;
      pt_value := coalesce(pj_1->>(pt_column), '');

      -- excluded columns - start
      pb_column_excluded := false;
      /*
      for k in 0..jsonb_array_length(pj_excluded) - 1 loop
        pt_column_excluded := ((pj_excluded)::jsonb->>k)::text;
        if pt_column = pt_column_excluded then
          pb_column_excluded := true;
          exit;
        end if;
      end loop;
      */

      if pb_column_excluded = false then

        pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column)).ot_1;
        if pt_udt_name <> '' then
          if pt_value = '' then
            pt_value := 'null';
          else
            if pt_udt_name = 'varchar' or pt_udt_name = 'timestamp' then
                pt_value := a || pt_value || a;
            end if;
          end if;

          if pt_column = pt_column_id then
            pt_update_where := pt_update_where || pt_column || '=' || pt_value;
          end if;

        end if;

      end if;
      
    end loop;
    
    query := 'delete from ' || pt_schema || '.' || pt_table || ' where ' || pt_update_where;
    full_query := query || '; ';
    
    pt_3 := 'DEL';
    pj_1 := '[[' || '"' || pt_3 || '"' || ',' || '"' || full_query || '"'  || ',' || pj_4 || ']]';
    oj_1 := oj_1 || pj_1;
    -- sql - end

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  elsif pt_case = 'execute_update_row_detail' then
    on_code := 200;
    pn_code_error := 400;

    pt_1 := '';
    pt_2 := '';
    pj_4 := '[]';
    oj_1 := '[]';

    pt_action := split_part(it_plot_1, '|' , 2);
    pn_user_id := split_part(it_plot_1, '|' , 3);
    pn_group_id := split_part(it_plot_1, '|' , 4);
    pt_schema := split_part(it_plot_1, '|' , 5);
    pt_table := split_part(it_plot_1, '|' , 6);
    
    pt_column_id_N1 := split_part(it_plot_1, '|', 7);
    pt_column_id_N2 := split_part(it_plot_1, '|', 8);
    pt_column_id_N3 := split_part(it_plot_1, '|', 9);
    
    pn_max_level := split_part(it_plot_1, '|', 10);
    pn_level := split_part(it_plot_1, '|', 11);
    pt_N1 := split_part(it_plot_1, '|', 12);
    pt_N2 := split_part(it_plot_1, '|', 13);
    pt_N3 := split_part(it_plot_1, '|', 14);

    --pt_N2_reference_id := split_part(it_plot_1, '|', 15);

    --ij_data jsonb,
    pj_equivalent := ij_1;
    pj_excluded := ij_2;

    if pn_level = 1 then
      pt_column_id := pt_column_id_N1;
    elsif pn_level = 2 then
      pt_column_id := pt_column_id_N2;
    elsif pn_level = 3 then
      pt_column_id := pt_column_id_N3;
    end if;

    -- sql - start
    pj_1 := ij_data;
    pj_2 := (select json_agg(t) from (select jsonb_object_keys(pj_1) as column) t)::jsonb;
--developer_text := 'fernando1';
--developer_jsonb := pj_1;
    pt_update_set := '';
    pt_update_where := '';

    for j in 0..jsonb_array_length(pj_2) - 1 loop
      pj_3 := (pj_2)::jsonb->j;
      pt_column := (pj_3->>'column')::text;
      --pt_value := coalesce(pj_1->>(pt_column), '');

      pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column)).ot_1;
      if pt_udt_name <> '' and pt_udt_name = 'jsonb' then
        pj_4 := coalesce((pj_1->>pt_column)::jsonb, '[]');
      else
        pt_value := coalesce(pj_1->>(pt_column), '');
      end if;

      -- excluded columns - start
      pb_column_excluded := false;
      for k in 0..jsonb_array_length(pj_excluded) - 1 loop
        pt_column_excluded := ((pj_excluded)::jsonb->>k)::text;
        if pt_column = pt_column_excluded then
          pb_column_excluded := true;
          exit;
        end if;
      end loop;

      if pt_column = 'group_id' then
        pb_column_excluded := true;
      end if;
      -- excluded columns - end

      if pb_column_excluded = false then

        pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column)).ot_1;
        if pt_udt_name <> '' then
          if pt_value = '' then
            pt_value := 'null';
          else
            if pt_udt_name = 'varchar' or pt_udt_name = 'text' or pt_udt_name = 'timestamp' then
              pt_value := a || pt_value || a;
            elsif pt_udt_name = 'jsonb' then
              if jsonb_array_length(pj_4) > 0 then
                pt_value := a || a1 || '_jsonb' || a || '::jsonb';
              else
                pt_value := 'null';
              end if;
            end if;
          end if;

          if pt_column = pt_column_id then
            pt_update_where := pt_update_where || pt_column || '=' || pt_value;
            pt_1 := pt_value;
          else
            if pt_column = 'parent_id' then
              pt_2 := pt_value;
            end if;
            pt_update_set := pt_update_set || pt_column || '=' || pt_value || ', ';
          end if;

        end if;

      end if;
      
    end loop;

    pt_update_set := substr(pt_update_set, 1, length(pt_update_set) - 2);
    query := 'update ' || pt_schema || '.' || pt_table || ' set ' || pt_update_set || ' where ' || pt_update_where;

    if (pn_level = 1 or pn_level < pn_max_level) then
      if pt_column_id = '' then
        full_query := query || '; ';
      else
        full_query := query || ' returning jsonb_build_object(' || a || pt_column_id || a || ', ' || pt_column_id || '), ' || pt_column_id || ';';
      end if;
    else
      full_query := query || '; ';
    end if;

    if pn_level = 1 then
      pt_3 := a1 || pt_N1;
    elsif pn_level = 2 then
      pt_3 := a1 || pt_N2;
    elsif pn_level = 3 then
      pt_3 := '';
    end if;

    -- 28/11/2025: cambio por tema de xml
    pj_1 := jsonb_build_array(
        jsonb_build_array(
            pt_3,
            full_query,
            pj_4::jsonb
        )
    );
    --pj_1 := '[[' || '"' || pt_3 || '"' || ',' || '"' || full_query || '"'  || ',' || pj_4 || ']]';
    oj_1 := oj_1 || pj_1;

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  elsif pt_case = 'execute_insert_row_detail' then
    on_code := 200;
    pn_code_error := 400;

    oj_1 := '[]';
    pj_4 := '[]';
    pb_group_id = false;

    pt_action := split_part(it_plot_1, '|' , 2);
    pn_user_id := split_part(it_plot_1, '|' , 3);
    pn_group_id := split_part(it_plot_1, '|' , 4);
    pt_schema := split_part(it_plot_1, '|' , 5);
    pt_table := split_part(it_plot_1, '|' , 6);
    
    pt_column_id_N1 := split_part(it_plot_1, '|', 7);
    pt_column_id_N2 := split_part(it_plot_1, '|', 8);
    pt_column_id_N3 := split_part(it_plot_1, '|', 9);
    
    pn_max_level := split_part(it_plot_1, '|', 10);
    pn_level := split_part(it_plot_1, '|', 11);
    pt_N1 := split_part(it_plot_1, '|', 12);
    pt_N2 := split_part(it_plot_1, '|', 13);
    pt_N3 := split_part(it_plot_1, '|', 14);

    --pt_N2_reference_id := split_part(it_plot_1, '|', 15);

    pb_equal_tables := split_part(it_plot_1, '|', 15);

    pj_line_data := ij_data;
    pj_equivalent := ij_1;
    pj_excluded := ij_2;

    if pn_level = 1 then
      pt_column_id := pt_column_id_N1;
    elsif pn_level = 2 then
      pt_column_id := pt_column_id_N2;
    elsif pn_level = 3 then
      pt_column_id := pt_column_id_N3;
    end if;

    -- sql - start
    pt_insert_columns := '';
    pt_insert_values := '';

    if pn_level = 2 then

      if pb_equal_tables = false then
        pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column_id_N1)).ot_1;
        if pt_udt_name <> '' then
          pt_insert_columns := pt_column_id_N1 || ', ';
          pt_insert_values := a1 || pt_N1 || ', ';
        end if;
      end if;
    
    elsif pn_level = 3 then

      pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column_id_N1)).ot_1;
      if pt_udt_name <> '' then
        pt_insert_columns := pt_column_id_N1 || ', ';
        pt_insert_values := a1 || pt_N1 || ', ';
      end if;

      pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column_id_N2)).ot_1;
      if pt_udt_name <> '' then
        pt_insert_columns := pt_insert_columns || pt_column_id_N2 || ', ';
        pt_insert_values := pt_insert_values || a1 || pt_N2 || ', ';
      end if;

    end if;

    pj_1 := pj_line_data;
    pj_2 := (select json_agg(t) from (select jsonb_object_keys(pj_1) as column) t)::jsonb;

    for j in 0..jsonb_array_length(pj_2) - 1 loop
      pj_3 := (pj_2)::jsonb->j;
      pt_column := (pj_3->>'column')::text;

      pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column)).ot_1;
      if pt_udt_name <> '' and pt_udt_name = 'jsonb' then
        pj_4 := coalesce((pj_1->>pt_column)::jsonb, '[]');
      else
        pt_value := coalesce(pj_1->>(pt_column), '');
      end if;

      -- excluded columns - start
      pb_column_excluded := false;
      for k in 0..jsonb_array_length(pj_excluded) - 1 loop
        pt_column_excluded := ((pj_excluded)::jsonb->>k)::text;
        if pt_column = pt_column_excluded then
          pb_column_excluded := true;
          exit;
        end if;
      end loop;

      if 
         (pt_action = 'i' and pt_column = pt_column_id)
      or (pt_action = 'i' and pn_level = 2 and pt_column = pt_column_id_N1)
      or (pt_action = 'i' and pn_level = 3 and (pt_column = pt_column_id_N1 or pt_column = pt_column_id_N2))
      then
        pb_column_excluded := true;
      end if;
      -- excluded columns - end

      if pb_column_excluded = false then
        
        if pt_udt_name <> '' then

          if pt_column = 'group_id' then
            pt_value := pn_group_id::text;
            pb_group_id = true;
          end if;

          if pt_column = 'parent_id' and pn_level = 2 and pb_equal_tables = true then
            pt_value := a1 || pt_N1;
          end if;

          pt_insert_columns := pt_insert_columns || pt_column || ', ';
          if pt_value = '' then
            pt_value := 'null';
          else
          
            if pt_udt_name = 'varchar' or pt_udt_name = 'text' or pt_udt_name = 'timestamp' then
              pt_value := a || pt_value || a;
            elsif pt_udt_name = 'jsonb' then
              if jsonb_array_length(pj_4) > 0 then
                pt_value := a || a1 || '_jsonb' || a || '::jsonb';
              else
                pt_value := 'null';
              end if;
            end if;
            
          end if;
          pt_insert_values := pt_insert_values || pt_value || ', ';
        end if;

      end if;
      
    end loop;

    if pb_group_id = false then
      pt_column := 'group_id';
      pt_udt_name := (fnc_config_tools_crud(it_plot_1 => 'get_column_type' || '|' || pt_schema || '|' || pt_table || '|' || pt_column)).ot_1;
      if pt_udt_name <> '' then
        pt_value := pn_group_id::text;
        pt_insert_columns := pt_insert_columns || pt_column || ', ';
        pt_insert_values := pt_insert_values || pt_value || ', ';
      end if;
    end if;

    pt_insert_columns := substr(pt_insert_columns, 1, length(pt_insert_columns) - 2);
    pt_insert_values := substr(pt_insert_values, 1, length(pt_insert_values) - 2);
    query := 'insert into ' || pt_schema || '.' || pt_table || ' (' || pt_insert_columns || ') values (' || pt_insert_values || ')';

    if pt_column_id = '' then
      full_query := query || '; ';
    else
      full_query := query || ' returning jsonb_build_object(' || a || pt_column_id || a || ', ' || pt_column_id || '), ' || pt_column_id || ';';
    end if;

    --if (pn_level = 1 or pn_level < pn_max_level) then
      /*
      if pt_column_id = '' and pt_N2_reference_id = '' then
        full_query := query || '; ';
      else
        if pt_column_id = '' and pt_N2_reference_id <> '' then
          pt_column_id := pt_N2_reference_id;
        end if;
        full_query := query || ' returning jsonb_build_object(' || a || pt_column_id || a || ', ' || pt_column_id || '), ' || pt_column_id || ';';
      end if;
      */
    --else
    --  full_query := query || '; ';
    --end if;

    if pn_level = 1 then
      pt_3 := a1 || pt_N1;
    elsif pn_level = 2 then
      pt_3 := a1 || pt_N2;
    elsif pn_level = 3 then
      pt_3 := '';
    end if;

    pj_1 := '[[' || '"' || pt_3 || '"' || ',' || '"' || full_query || '"'  || ',' || pj_4 || ']]';
    oj_1 := oj_1 || pj_1;

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  elsif pt_case = 'execute_s2' then
    on_code := 201;
    pn_code_error := 401;

    pj_columns := '[]';

    pn_group_id := split_part(it_plot_1, '|' , 2);
    -- ij_data
    pj_table_config := ij_1;

    -- process
    pj_1 := ((pj_table_config)::jsonb->0);
    pj_2 := (pj_1->>'s2');
    if pj_2 is not null then
      pt_schema := (pj_2->>'schema')::text;
      pt_table := (pj_2->>'table')::text;
      pj_columns := coalesce((pj_2->>'columns')::jsonb, '[]');
    else
      pt_schema := (pj_1->>'schema')::text;
      pt_table := (pj_1->>'table')::text;
      pt_column_id := (pj_1->>'column_id')::text;
      pt_column_name := (pj_1->>'column_name')::text;
      pj_columns := '
      [
        {"column": "' || pt_column_id || '", "as": "' || pt_column_id || '"},
        {"column": "' || pt_column_name || '", "as": "' || pt_column_name || '"},
        {"column": "' || pt_column_id || '", "as": "value"},
        {"column": "' || pt_column_name || '", "as": "label"}
      ]';
    end if;

    pj_2 := '[]';
    for i in 0..jsonb_array_length(pj_columns)-1 loop
      pj_1 := ((pj_columns)::jsonb->i);
      pt_column := (pj_1->>'as');
      pt_value := (pj_1->>'column');
      pt_value := pt_table || '.' || pt_value;

      pj_3 := '[[' || '"' || pt_column || '"' || ',' || '"' || pt_value || '"'  || ']]';
      pj_2 := pj_2 || pj_3;
    end loop;

    if pt_schema <> '' then
      pt_table := pt_schema || '.' || pt_table;
    end if;

    pt_sql := '
    select 
      json_agg(jsonb_build_object(' || 
      (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => pj_2)).ot_1 || '
      )) 
    from ' || pt_table || ' 
    where 
    ' || pt_table || '.group_id = ' || pn_group_id;

    if jsonb_typeof(ij_data) = 'array' and jsonb_array_length(ij_data) > 0 then
      for i in 0..jsonb_array_length(ij_data)-1 loop
        pj_1 := ((ij_data)::jsonb->i);
        pt_column := (pj_1->>'column');
        pt_value := (pj_1->>'value');
        pt_column := pt_table || '.' || pt_column;

        pt_sql := pt_sql || ' and ' || pt_column || '=' || a || pt_value || a;
      end loop;
    end if;

    execute pt_sql into oj_data;

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  elsif pt_case = 'execute_update_rows_state' then
    on_code := 203;
    pn_code_error := 403;

    pt_action := split_part(it_plot_1, '|' , 2);
    pt_schema := split_part(it_plot_1, '|' , 3);
    pt_table := split_part(it_plot_1, '|' , 4);
    pt_column_id := split_part(it_plot_1, '|' , 5);

    pt_column := 'state';

    if pt_action = 'sa' then
      pt_value := 'I';
    elsif pt_action = 'sd' then
      pt_value := 'A';
    elsif pt_action = 'us' then
      pt_value := ij_data ->> 'state';
      ij_data := '[' || (ij_data ->> pt_column_id)::text  || ']';
    
    elsif pt_action = 'us2' then
      pt_column := coalesce((ij_data ->> 'column'), 'state');
      ij_data := '[' || (ij_data ->> pt_column_id)::text  || ']';

      begin
        select
          udt_name into pt_udt_name 
        from
          information_schema.columns 
        where 
          table_schema = pt_schema and table_name = pt_table and column_name = pt_column;
      exception
      when no_data_found then
        pt_udt_name := '';
      end;

    end if;

    -- IDs process - start
    pt_values := '';
    for i in 0..jsonb_array_length(ij_data)-1 loop
      pt_values := pt_values || (((ij_data)::jsonb->>i)::jsonb->>0)::text || ', ';
    end loop;
    pt_values := substr(pt_values, 1, length(pt_values) - 2);
    -- IDs process - end

    if pt_action = 'us2' then
      if pt_udt_name = 'varchar' then
        pt_sql := 'select case when ' || pt_column || ' = ' || a || 'A' || a || ' then ' || a || 'I' || a || ' else ' || a || 'A' || a || ' end ' || pt_column || ' from ' || pt_schema || '.' || pt_table || ' where ' || pt_column_id || ' in (' || pt_values || ')';
      elsif pt_udt_name = 'bool' then
        pt_sql := 'select case when ' || pt_column || ' = true then false else true end ' || pt_column || ' from ' || pt_schema || '.' || pt_table || ' where ' || pt_column_id || ' in (' || pt_values || ')';
      end if;
      pt_value := ' (' || pt_sql || ') ';
    else
      pt_value := a || pt_value || a;
    end if;

    -- sql - start
    pt_sql := 'update ' || pt_schema || '.' || pt_table || ' set ' || pt_column || ' = ' || pt_value || ' where ' || pt_column_id || ' in (' || pt_values || ')';
    if jsonb_array_length(ij_data) = 1 then
      pt_sql := pt_sql || ' returning jsonb_build_object(' || a || pt_column_id || a || ', ' || pt_column_id || ')';
      execute pt_sql into oj_data;
    else
      execute pt_sql;
    end if;
    -- sql - end
    
    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  elsif pt_case = 'execute_delete_rows' then
    on_code := 204;
    pn_code_error := 404;

    pt_schema := split_part(it_plot_1, '|' , 2);
    pt_table := split_part(it_plot_1, '|' , 3);
    pt_column_id := split_part(it_plot_1, '|' , 4);

    -- IDs process - start
    pt_values := '';
    for i in 0..jsonb_array_length(ij_data)-1 loop
      pt_values := pt_values || (((ij_data)::jsonb->>i)::jsonb->>0)::text || ', ';
    end loop;
    pt_values := substr(pt_values, 1, length(pt_values) - 2);
    -- IDs process - end

    pt_sql := 'delete from ' || pt_schema || '.' || pt_table || ' where ' || pt_column_id || ' in (' || pt_values || ')';
    execute pt_sql;

    oj_info := fnc_config_message(on_code, developer_text, developer_jsonb);

  end if;

  return next;
exception
  when others then
    GET STACKED DIAGNOSTICS pt_message_text = MESSAGE_TEXT,
                            pt_constraint_name = CONSTRAINT_NAME,
                            pt_pg_exception_hint = PG_EXCEPTION_HINT,
                            pt_pg_exception_detail = PG_EXCEPTION_DETAIL;

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
