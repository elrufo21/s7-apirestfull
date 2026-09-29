import {
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';

import { TenantDatabaseService } from '../tenant-database/tenant-database.service';
import { ExecuteDto } from './dto/execute.dto';
import type { JwtPayload } from '../auth/jwt-auth.guard';
import { RealtimeService } from '../realtime/realtime.service';

const READ_ACTIONS = new Set(['s', 's1', 's2', 's3', 's4', 's_pos']);

export function getPaymentInvoiceLinkInput(
  data: unknown,
  rows: Array<Record<string, unknown>>,
) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return null;
  }

  const paymentId = Number(
    (rows[0]?.oj_data as Record<string, unknown> | undefined)?.payment_id,
  );
  const moveId = Number((data as Record<string, unknown>).move_id);
  const amount = Number((data as Record<string, unknown>).amount);

  if (![paymentId, moveId, amount].every((value) => Number.isFinite(value) && value > 0)) {
    return null;
  }

  return { paymentId, moveId, amount };
}

export function getDefaultProductImage(files: unknown): unknown | null {
  if (!Array.isArray(files) || files.length === 0) {
    return null;
  }

  const hasExplicitDefault = files.some(
    (file) =>
      file &&
      typeof file === 'object' &&
      typeof (file as Record<string, unknown>).isDefault === 'boolean',
  );

  if (!hasExplicitDefault) {
    return files[0];
  }

  return (
    files.find(
      (file) =>
        file &&
        typeof file === 'object' &&
        (file as Record<string, unknown>).isDefault === true,
    ) ?? null
  );
}

@Injectable()
export class ExecutorService {
  private readonly logger = new Logger(ExecutorService.name);

  constructor(
    private readonly tenantDatabaseService: TenantDatabaseService,
    private readonly realtimeService: RealtimeService,
  ) {}

  async execute(dto: ExecuteDto, authenticatedUser: JwtPayload) {
    const userId = authenticatedUser.userId ?? dto.userId;
    const groupId = authenticatedUser.groupId ?? dto.groupId;

    const database = authenticatedUser.database;

    const companies = dto.companies ?? [];
    const action = dto.action ?? '';
    const data = dto.data ?? [];

    if (!userId) {
      throw new InternalServerErrorException(
        'No se pudo determinar el usuario',
      );
    }

    if (!groupId) {
      throw new InternalServerErrorException(
        'No se pudo determinar el grupo del usuario',
      );
    }

    // Soporte directo para funciones RPC standalone de persistencia EDI
    if (dto.functionName === 'fnc_account_move_update_edi') {
      const payload = Array.isArray(data) ? data[0] : (data || {});
      const moveId = payload?.in_move_id || payload?.move_id;
      const xmlReq = payload?.it_edi_xml_request || payload?.edi_xml_request || '';
      const xmlRes = payload?.it_edi_xml_response || payload?.edi_xml_response || '';
      const ediState = payload?.it_edi_state || payload?.edi_state || 'S';
      const ediCode = String(payload?.it_edi_code ?? payload?.edi_code ?? '0');
      const ediMessage = String(payload?.it_edi_message ?? payload?.edi_message ?? '');

      const ediSql = `
        SELECT * FROM public.fnc_account_move_update_edi(
          $1::bigint,
          $2::text,
          $3::text,
          $4::text,
          $5::text,
          $6::text
        )
      `;
      const rows = await this.tenantDatabaseService.query(
        database,
        ediSql,
        [moveId, xmlReq, xmlRes, ediState, ediCode, ediMessage],
      );

      this.realtimeService.broadcast({
        type: 'invoice.changed',
        payload: { action: 'u', moveId, at: new Date().toISOString() },
      });

      return rows;
    }

    if (dto.functionName === 'fnc_account_move_audit_insert') {
      const payload = Array.isArray(data) ? data[0] : (data || {});
      const groupIdVal = payload?.in_group_id || groupId;
      const filesVal = JSON.stringify(payload?.ij_files || []);
      const userIdVal = payload?.in_user_id || userId;
      const creationDateVal = payload?.id_creation_date || new Date().toISOString();
      const moveIdVal = payload?.in_move_id || payload?.move_id;
      const actionIdVal = payload?.it_action_id || 'S1';
      const ediCodeVal = String(payload?.it_edi_code || '0');
      const ediMessageVal = String(payload?.it_edi_message || '');

      const auditSql = `
        SELECT * FROM public.fnc_account_move_audit_insert(
          $1::bigint,
          $2::jsonb,
          $3::bigint,
          $4::timestamp without time zone,
          $5::bigint,
          $6::text,
          $7::text,
          $8::text
        )
      `;
      const rows = await this.tenantDatabaseService.query(
        database,
        auditSql,
        [groupIdVal, filesVal, userIdVal, creationDateVal, moveIdVal, actionIdVal, ediCodeVal, ediMessageVal],
      );

      return rows;
    }

    const sql = `
      SELECT *
      FROM public.fnc_execute(
        $1::text,
        $2::integer,
        $3::integer,
        $4::jsonb,
        $5::text,
        $6::jsonb
      )
    `;
    const parameters = [
      dto.functionName,
      userId,
      groupId,
      JSON.stringify(companies),
      action,
      JSON.stringify(data),
    ];
    const rows = await this.tenantDatabaseService.query(
      database,
      sql,
      parameters,
    );

    if (dto.functionName === 'fnc_account_move' && !READ_ACTIONS.has(action)) {
      await this.syncSaleOrderInvoicedTotalsIfNeeded({
        database,
        data,
        groupId,
        rows,
        userId,
      });

      this.realtimeService.broadcast({
        type: 'invoice.changed',
        payload: { action, at: new Date().toISOString() },
      });
    }

    if (
      dto.functionName === 'fnc_product_template' &&
      !READ_ACTIONS.has(action)
    ) {
      await this.syncProductDefaultImageIfNeeded({
        database,
        data,
        groupId,
        rows,
      });
    }

    return rows;
  }

  private async syncProductDefaultImageIfNeeded({
    database,
    data,
    groupId,
    rows,
  }: {
    database: string;
    data: unknown;
    groupId: number;
    rows: Array<Record<string, unknown>>;
  }) {
    if (
      !this.wasExecutionSuccessful(rows) ||
      !data ||
      typeof data !== 'object' ||
      Array.isArray(data) ||
      !Object.prototype.hasOwnProperty.call(data, 'files')
    ) {
      return;
    }

    const productTemplateId = this.toPositiveNumber(
      this.getObjectValue(data, 'product_template_id') ??
        this.getResponseValue(rows, 'oj_data', 'product_template_id'),
    );

    if (!productTemplateId) {
      return;
    }

    const defaultImage = getDefaultProductImage(
      this.getObjectValue(data, 'files'),
    );

    await this.tenantDatabaseService.query(
      database,
      `
        UPDATE public.product
        SET files = $1::jsonb
        WHERE product_template_id = $2
          AND group_id = $3
      `,
      [
        defaultImage ? JSON.stringify([defaultImage]) : null,
        productTemplateId,
        groupId,
      ],
    );
  }


  private async syncSaleOrderInvoicedTotalsIfNeeded({
    database,
    data,
    groupId,
    rows,
    userId,
  }: {
    database: string;
    data: unknown;
    groupId: number;
    rows: Array<Record<string, unknown>>;
    userId: number;
  }) {
    if (!this.wasExecutionSuccessful(rows) || !this.isRegisteredInvoice(data)) {
      return;
    }

    const moveId = this.toPositiveNumber(
      this.getResponseValue(rows, 'oj_data', 'move_id') ??
        this.getObjectValue(data, 'move_id'),
    );

    if (!moveId) {
      return;
    }

    try {
      const syncRows = await this.tenantDatabaseService.query(
        database,
        `
          SELECT *
          FROM public.fnc_sale_order_sync_invoiced_from_move(
            $1::bigint,
            $2::bigint,
            $3::bigint
          )
        `,
        [moveId, userId, groupId],
      );

      if (!this.wasExecutionSuccessful(syncRows)) {
        throw new Error('La función SQL devolvió error al sincronizar.');
      }
    } catch (error) {
      this.logger.error(
        'Error sincronizando cantidades facturadas de orden de venta',
        error instanceof Error ? error.stack : String(error),
      );
      throw new InternalServerErrorException(
        'Factura registrada, pero no se pudo sincronizar cantidades facturadas de la orden de venta',
      );
    }
  }

  private wasExecutionSuccessful(rows: Array<Record<string, unknown>>) {
    const type = this.getResponseValue(rows, 'oj_info', 'type');
    return typeof type === 'string' && type.toLowerCase() === 'success';
  }

  private isRegisteredInvoice(data: unknown) {
    return this.getObjectValue(data, 'state') === 'R';
  }

  private getObjectValue(data: unknown, key: string) {
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      return undefined;
    }

    return (data as Record<string, unknown>)[key];
  }

  private getResponseValue(
    rows: Array<Record<string, unknown>>,
    objectKey: string,
    valueKey: string,
  ) {
    return this.getObjectValue(rows[0]?.[objectKey], valueKey);
  }

  private toPositiveNumber(value: unknown) {
    const numberValue = Number(value);
    return Number.isFinite(numberValue) && numberValue > 0 ? numberValue : null;
  }
}
