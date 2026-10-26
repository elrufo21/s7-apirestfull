CREATE OR REPLACE FUNCTION public.fnc_payment(in_user_id integer, in_group_id integer, ij_companies jsonb, it_action text, ij_data jsonb)
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
        pr_rec record;
        pj_1 jsonb;
        pj_2 jsonb;
        pj_columns jsonb;
        --pt_type text;

		pt_1 text;

        -- dynamic variables
        pt_sql text;
        a text := '''';
        pt_get_search_column text := '(fnc_config_tools(it_plot_1 => ' || a || 'get_search_column' || '|' || a || ' || @column)).ot_1';
        pt_config_type text;
        pt_config_filter_key text;
        pt_config_filter_value text;
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
        pt_fnc text := 'fnc_payment';
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

        pj_table_config jsonb := '
        [
          {
          "schema": "public",
          "table": "payment",
          "column_id": "payment_id",
          "column_name_s2": "full_name",
          "columns_copy": ["name"],
          "column_sort": "payment_id",
          "direction_sort": "desc",
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

        pn_payment_account_move__move_id int;
        pn_payment_account_move__payment_id int;
        pt_account_partial_reconcile__credit_type text;
         
      begin

        if it_action = 'r' or it_action = 'd' then
          pb_list_select_all := (fnc_config_tools(it_plot_1 => 'list_select_all', ij_data => ij_data)).ob_1;
        elsif it_action = 's2' then
          pt_s2_columns := (fnc_config_tools(it_plot_1 => 's2_columns', ij_1 => pj_table_config, ij_2 => pj_columns_alias, ij_data => ij_data)).ot_1;
        end if;

        if it_action = 's' or it_action = 's2' or pb_list_select_all = true then

          /* --------------------------------------------------------------------------------------------------
          |                                        process filters - start
          */---------------------------------------------------------------------------------------------------

          pt_filter_state := '';
          for i in 0..jsonb_array_length(ij_data)-1 loop
		      pj_1 := ((ij_data)::jsonb->>i)::jsonb;
		      pt_config_type := pj_1->>1;
		      pt_config_filter_key := '';
		
		      if pt_config_type = 'fbetween' then
		        pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'fbetween', ij_1 => pj_1, ij_2 => pj_columns_alias)).ot_1;
		      elsif pt_config_type = 'fequal' then
		        if pj_1->>2 = 'move_id' then
		          pt_config_filter_value := pj_1->>3;
		          if position('debit_move_id = ' || pt_config_filter_value in pt_filter_categories) = 0 then
		            pt_filter_categories := pt_filter_categories || ' and (t1.payment_id in (select credit_move_id from public.account_partial_reconcile where debit_move_id = ' || pt_config_filter_value || ' and credit_type = ''payment'') or t1.move_id = ' || pt_config_filter_value || ')';
		          end if;
		        else
		          pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'fequal', ij_1 => pj_1, ij_2 => pj_columns_alias)).ot_1;
		        end if;
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
            
            if pt_config_filter_key = 'name' then
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

            elsif pt_config_filter_key = '1' then
              pt_config_filters_columns := pt_config_filters_columns || (fnc_config_tools(it_plot_1 => 'multi_filter_in', ij_1 => pj_columns_alias, ij_2 => pj_config_filter_values)).ot_1;
            
            elsif pt_config_filter_key = 'account_partial_reconcile' then
              pt_config_filter_value := ((pj_1->>2)::jsonb->>0)::text;
              if position('debit_move_id = ' || pt_config_filter_value in pt_filter_categories) = 0 then
                pt_filter_categories := pt_filter_categories || ' and (t1.payment_id in (select credit_move_id from public.account_partial_reconcile where debit_move_id = ' || pt_config_filter_value || ' and credit_type = ''payment'') or t1.move_id = ' || pt_config_filter_value || ')';
              end if;
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
              tmp_base := 'payment';
            end if;

            /* --------------------------------------------------------------------------------------------------
            |                                    process: temporary tables - end
            */---------------------------------------------------------------------------------------------------

            pt_config_filters := pt_config_filters || pt_filter_categories;
            --developer_text := pt_config_filters;

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
          -- configuration values - end

          if pb_extract_final_data = true then

            -- final data - start
            if it_action = 's' then
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
                ["journal_name", "jou.name"],
                ["partner_name", "con.name"],
                ["payment_method_name", "mpay.name"],
                ["currency_name", "div.name"],
          ["CASE_WHEN", "origin_description", "t1.origin", [["account_move","Factura"],["payment","Pago"]]],
          ["CASE_WHEN", "type_description", "t1.payment_type", [["inbound","Recibir"],["outbound","Enviar"]]], ["CASE_WHEN", "payment_type_description", "t1.payment_type", [["inbound","Recibir"],["outbound","Enviar"]]],
                ["CASE_WHEN", "state_description", "t1.state", [["draft","Borrador"],["posted","Pagado"],["rejected","Rechazado"],["cancel","Cancelado"],["posted_cancel","Cancelado"]]]

                ]')).ot_1 

                || ', ' || a || 'amount_in_currency' || a || ', (div.symbol || ' || a || ' ' || a || ' || to_char(t1.amount, ' || a || '99999999999.99' || a || ')) '

              || ') '
              -- Block 2 - end

              || ' order by t1.payment_id desc) 
              ';
            elsif it_action = 's2' then
              pt_base_table_columns_query := 'json_agg(jsonb_build_object(' || pt_s2_columns || ') order by t1.payment_id desc)';
            end if;

            pt_sql := '
            select ' ||
              pt_base_table_columns_query || ' 
            from 
              ' || tmp_data || ' t1
              left join public.partner con on con.partner_id = t1.partner_id 
              left join public.journal jou on jou.journal_id = t1.journal_id 
              left join public.payment_method mpay on mpay.payment_method_id = t1.payment_method_id
              left join public.currency div on div.currency_id = t1.currency_id 

              left join public.company cia on cia.company_id = t1.company_id 
              left join public.partner con_cia on con_cia.partner_id = cia.partner_id 
              ';
              execute pt_sql into oj_data;
              -- final data - end

          end if;

          oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb, pn_base_table_count);

        when it_action = 's1' then
          pn_code := 200;
          pn_code_error := 400;
          pn_row_id := (((ij_data)::jsonb->>0)::jsonb->>0)::text;

          pt_sql := '
          select
            json_agg('
            
            -- block 1 - start
            || 'jsonb_build_object(' || 
            (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'payment' || '|' || 't1')).ot_1 || ', ' || 

            (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
            '[
              ["company_name", "con_cia.name"],
              ["journal_name", "jou.name"],
              ["partner_name", "con.name"],
              ["payment_method_name", "mpay.name"],
              ["currency_name", "div.name"],
          ["CASE_WHEN", "origin_description", "t1.origin", [["account_move","Factura"],["payment","Pago"]]],
          ["CASE_WHEN", "type_description", "t1.payment_type", [["inbound","Recibir"],["outbound","Enviar"]]], ["CASE_WHEN", "payment_type_description", "t1.payment_type", [["inbound","Recibir"],["outbound","Enviar"]]],
              ["CASE_WHEN", "state_description", "t1.state", [["draft","Borrador"],["posted","Pagado"],["rejected","Rechazado"],["cancel","Cancelado"],["posted_cancel","Cancelado"]]]
            ]')).ot_1 

            || ', ' || a || 'audit' || a || ', 
            (' || 
              'select coalesce(json_agg(jsonb_build_object(' ||
              (fnc_config_tools(it_plot_1 => 'query_all_columns|' || 'public' || '|' || 'payment_audit' || '|' || 'aud')).ot_1 || ', ' || 
              (fnc_config_tools(it_plot_1 => 'query_columns', ij_1 => 
              '[
                ["type", "act.type"],
                ["action", "act.action"],
                ["description", "act.description"],
                ["user_name", "con_aud.name"],
                ["user_files", "con_aud.files"]
              ]')).ot_1 ||
              '
              ) order by aud.creation_date asc), ''[]''::json) 
              from 
                public.payment_audit aud 
                left join public.audit_action act on aud.action_id = act.action_id 
                left join public."user" usu on aud.user_id = usu.user_id 
                left join public.partner con_aud on usu.partner_id = con_aud.partner_id 
              where 
                aud.payment_id = t1.payment_id 
            )'

            || ', ' || a || 'invoices' || a || ', 
            (
              select coalesce(json_agg(jsonb_build_object(
                ''move_id'', am.move_id,
                ''name'', am.name,
                ''state'', am.state,
                ''amount_withtaxed'', am.amount_withtaxed,
                ''payment_amount'', pam.amount
              )), ''[]''::json)
              from (
                select debit_move_id as move_id, amount from public.account_partial_reconcile where credit_move_id = t1.payment_id
                union all
                select t1.move_id, t1.amount where t1.move_id is not null and not exists (select 1 from public.account_partial_reconcile where credit_move_id = t1.payment_id and debit_move_id = t1.move_id)
              ) pam
              inner join public.account_move am on (pam.move_id = am.move_id)
            )'

            || ', ' || a || 'stat_invoices' || a || ', 
            (
              select coalesce(count(*), 0)
              from (
                select debit_move_id as move_id from public.account_partial_reconcile where credit_move_id = t1.payment_id
                union
                select t1.move_id where t1.move_id is not null
              ) pam_count
            )'

            || ')'
            -- block 1 - end

            || ') 
          from 
            public.payment t1
            left join public.partner con on con.partner_id = t1.partner_id 
            left join public.journal jou on jou.journal_id = t1.journal_id 
            left join public.payment_method mpay on mpay.payment_method_id = t1.payment_method_id
            left join public.currency div on div.currency_id = t1.currency_id 

            left join public.company cia on cia.company_id = t1.company_id 
            left join public.partner con_cia on con_cia.partner_id = cia.partner_id 
          where 
            t1.payment_id = ' || pn_row_id;
          
          execute pt_sql into oj_data;
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
        
        when it_action = 'i2' or it_action = 'i3' then

			pj_1 := ij_data;
			pn_payment_account_move__move_id := (pj_1 ->> 'move_id');
			pn_payment_account_move__payment_id := (pj_1 ->> 'payment_id');
			pt_account_partial_reconcile__credit_type := (pj_1 ->> 'credit_type');

			-- Auto-detección de credit_type si no fue provisto
			if pt_account_partial_reconcile__credit_type is null or pt_account_partial_reconcile__credit_type = '' then
				if exists (select 1 from public.payment where payment_id = pn_payment_account_move__payment_id) then
					pt_account_partial_reconcile__credit_type := 'payment';
				elsif exists (select 1 from public.account_move where move_id = pn_payment_account_move__payment_id and move_type in ('out_refund', 'in_refund')) then
					select move_type into pt_account_partial_reconcile__credit_type from public.account_move where move_id = pn_payment_account_move__payment_id;
				else
					pt_account_partial_reconcile__credit_type := 'payment';
				end if;
			end if;

      	developer_text := pt_account_partial_reconcile__credit_type;

	      	if it_action = 'i2' then
	
	      		pr_fnc_result := fnc_account_partial_reconcile
	      	    (
	      	      in_debit_move_id => pn_payment_account_move__move_id,
	      		  in_credit_move_id => pn_payment_account_move__payment_id, 
	      		  in_credit_type => pt_account_partial_reconcile__credit_type
	      	    );
	      	    oj_info := pr_fnc_result.oj_info;
	      	    oj_data := pr_fnc_result.oj_data;
	      		
	      	elsif it_action = 'i3' then
	      		pn_code := 200;
	      		pn_code_error := 400;

				/* CÓDIGO ANTERIOR:
				if pt_account_partial_reconcile__credit_type = 'payment' then
		      		delete from public.account_partial_reconcile 
		      		where 
		      			debit_move_id = pn_payment_account_move__move_id
		      		and credit_move_id = pn_payment_account_move__payment_id
		      		and credit_type = pt_account_partial_reconcile__credit_type;
				elsif pt_account_partial_reconcile__credit_type = 'out_refund' then
					pt_account_partial_reconcile__credit_type := 'out_invoice';
		      		delete from public.account_partial_reconcile 
		      		where 
		      			debit_move_id = pn_payment_account_move__payment_id
		      		and credit_move_id = pn_payment_account_move__move_id
		      		and credit_type = pt_account_partial_reconcile__credit_type;
				end if;
				FIN CÓDIGO ANTERIOR */

				-- Buscar y eliminar la conciliación (soportando tanto si move_id es débito o crédito)
				for pr_rec in (
					select partial_reconcile_id, debit_move_id, credit_move_id, credit_type, coalesce(amount, 0) as amount
					from public.account_partial_reconcile
					where (debit_move_id = pn_payment_account_move__move_id and credit_move_id = pn_payment_account_move__payment_id)
					   or (debit_move_id = pn_payment_account_move__payment_id and credit_move_id = pn_payment_account_move__move_id)
				) loop
					delete from public.account_partial_reconcile where partial_reconcile_id = pr_rec.partial_reconcile_id;
					
					-- Actualizar saldos de la factura afectada (debit_move_id)
					update public.account_move am
					set 
						amount_paid = coalesce((select sum(amount) from public.account_partial_reconcile where debit_move_id = pr_rec.debit_move_id), 0),
						amount_to_be_paid = greatest(am.amount_withtaxed - coalesce((select sum(amount) from public.account_partial_reconcile where debit_move_id = pr_rec.debit_move_id), 0), 0),
						payment_state = case 
							when coalesce((select sum(amount) from public.account_partial_reconcile where debit_move_id = pr_rec.debit_move_id), 0) = 0 then 'not_paid'
							when greatest(am.amount_withtaxed - coalesce((select sum(amount) from public.account_partial_reconcile where debit_move_id = pr_rec.debit_move_id), 0), 0) = 0 then 'paid'
							else 'partial'
						end
					where am.move_id = pr_rec.debit_move_id;

					-- Restaurar saldo del crédito (pago o nota de crédito)
					if exists (select 1 from public.payment where payment_id = pr_rec.credit_move_id) then
						update public.payment
						set amount_residual = least(amount, greatest(coalesce(amount_residual, 0) + pr_rec.amount, 0))
						where payment_id = pr_rec.credit_move_id;
					elsif exists (select 1 from public.account_move where move_id = pr_rec.credit_move_id) then
						update public.account_move am
						set 
							amount_paid = coalesce((select sum(amount) from public.account_partial_reconcile where credit_move_id = pr_rec.credit_move_id), 0),
							amount_to_be_paid = greatest(am.amount_withtaxed - coalesce((select sum(amount) from public.account_partial_reconcile where credit_move_id = pr_rec.credit_move_id), 0), 0),
							payment_state = case 
								when coalesce((select sum(amount) from public.account_partial_reconcile where credit_move_id = pr_rec.credit_move_id), 0) = 0 then 'not_paid'
								when greatest(am.amount_withtaxed - coalesce((select sum(amount) from public.account_partial_reconcile where credit_move_id = pr_rec.credit_move_id), 0), 0) = 0 then 'paid'
								else 'partial'
							end
						where am.move_id = pr_rec.credit_move_id;
					end if;
				end loop;

	      		oj_info := fnc_config_message(pn_code, developer_text, developer_jsonb, pn_base_table_count);
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
;
