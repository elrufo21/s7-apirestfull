export interface ProcedureInfo {
  code: number;
  type: string;
  action: string;
  message: string;
}

export interface UserData {
  user_id: number;
  group_id: number;
  email: string;
  company_id: number | null;
  avatar: unknown;
  name: string;
}

export interface UserDataProcedureResult {
  oj_info: ProcedureInfo;
  oj_data: UserData[] | null;
}
