export interface LoginInfo {
  code: number;
  type?: string;
  message?: string;
  action?: string;
  sqlerrm?: string;
}

export interface LoginUser {
  user_id: number;
  group_id: number;
  database: string;

  name?: string;
  email?: string;
  state?: string;
  registration_date?: string;

  [key: string]: unknown;
}

export interface LoginProcedureResult {
  oj_info: LoginInfo;
  oj_data: LoginUser[] | null;
}
