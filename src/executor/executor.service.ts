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

    const rows = await this.tenantDatabaseService.query(
      database,
      `
        SELECT *
        FROM public.fnc_execute(
          $1::text,
          $2::integer,
          $3::integer,
          $4::jsonb,
          $5::text,
          $6::jsonb
        )
      `,
      [
        dto.functionName,
        userId,
        groupId,
        JSON.stringify(companies),
        action,
        JSON.stringify(data),
      ],
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

    return rows;
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
