export interface ConfirmSaleOrderContext {
  orderId: number;
  userId: number;
  groupId: number;
  database: string;
}

export interface ConfirmSaleOrderResult {
  order_id: number;
  move_id: number;
}

export interface DatabaseInfo {
  code?: number;
  type?: string;
  action?: string;
  message?: string;
  sqlstate?: string;
  sqlerrm?: string;
  message_text?: string;
  constraint_name?: string;
  pg_exception_hint?: string;
  pg_exception_detail?: string;
  [key: string]: unknown;
}

export interface ConfirmSaleOrderDatabaseRow {
  oj_info?: DatabaseInfo;
  oj_data?: Partial<ConfirmSaleOrderResult> | null;
}

export interface ConfirmSaleOrderResponse {
  success: true;
  message: string;
  data: ConfirmSaleOrderResult;
  database: {
    oj_info: DatabaseInfo;
  };
}
