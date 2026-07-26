import type { QueryResultRow } from 'pg';

export interface ExecuteFunctionResult extends QueryResultRow {
  oj_info: unknown;
  oj_data: unknown;
  oj_gby_data: unknown;
  oj_audit: unknown;
  oj_stat: unknown;
}
