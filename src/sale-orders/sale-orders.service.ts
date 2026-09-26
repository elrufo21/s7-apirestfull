import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';

import { RealtimeService } from '../realtime/realtime.service';
import { TenantDatabaseService } from '../tenant-database/tenant-database.service';
import type {
  ConfirmSaleOrderContext,
  ConfirmSaleOrderDatabaseRow,
  ConfirmSaleOrderResponse,
  DatabaseInfo,
} from './sale-orders.types';

@Injectable()
export class SaleOrdersService {
  private readonly logger = new Logger(SaleOrdersService.name);

  constructor(
    private readonly tenantDatabaseService: TenantDatabaseService,
    private readonly realtimeService: RealtimeService,
  ) {}

  async confirmOrder(
    context: ConfirmSaleOrderContext,
  ): Promise<ConfirmSaleOrderResponse> {
    const rows = await this.runConfirmFunction(context);
    const row = rows[0];

    if (!row) {
      throw new InternalServerErrorException(
        'La función de confirmación no devolvió información',
      );
    }

    const info = row.oj_info;

    if (!info) {
      throw new InternalServerErrorException(
        'La función de confirmación no devolvió oj_info',
      );
    }

    if (String(info.type).toLowerCase() !== 'success') {
      this.logger.error(
        'Error confirmando orden de venta',
        JSON.stringify(info),
      );
      throw this.toHttpException(info);
    }

    const orderId = this.toNumber(row.oj_data?.order_id ?? context.orderId);
    const moveId = this.toNumber(row.oj_data?.move_id);

    if (!orderId || !moveId) {
      throw new InternalServerErrorException(
        'La función de confirmación no devolvió order_id o move_id',
      );
    }

    this.realtimeService.broadcast({
      type: 'invoice.changed',
      payload: {
        action: 'confirm-sale-order',
        order_id: orderId,
        move_id: moveId,
        at: new Date().toISOString(),
      },
    });

    return {
      success: true,
      message:
        info.message ?? 'Orden confirmada y factura borrador creada.',
      data: {
        order_id: orderId,
        move_id: moveId,
      },
      database: {
        oj_info: info,
      },
    };
  }

  private async runConfirmFunction(context: ConfirmSaleOrderContext) {
    try {
      return await this.tenantDatabaseService.query<ConfirmSaleOrderDatabaseRow>(
        context.database,
        `
          WITH confirmed AS MATERIALIZED (
            SELECT
              result.oj_info,
              result.oj_data,
              (result.oj_data->>'order_id')::bigint AS order_id,
              (result.oj_data->>'move_id')::bigint AS move_id
            FROM public.fnc_sale_order_confirm_create_move(
              $1::bigint,
              $2::bigint,
              $3::bigint
            ) result
          ),
          repaired_line_taxes AS (
            INSERT INTO public.account_move_lines_taxes (
              line_id,
              tax_id,
              percentage,
              amount
            )
            SELECT
              aml.line_id,
              COALESCE(solt.tax_id, sot.tax_id),
              COALESCE(solt.percentage, tx.percentage),
              COALESCE(
                solt.amount,
                COALESCE(sot.amount, 0)
                  * COALESCE(aml.amount_tax_total, aml.amount_tax, 0)
                  / NULLIF(so.amount_tax, 0),
                0
              )
            FROM confirmed c
            INNER JOIN public.sale_order so
              ON so.order_id = c.order_id
            INNER JOIN public.account_move_lines aml
              ON aml.move_id = c.move_id
            LEFT JOIN public.sale_order_lines sol
              ON sol.order_id = c.order_id
             AND sol.sequence = aml.position
            LEFT JOIN public.sale_order_lines_taxes solt
              ON solt.line_id = sol.line_id
            LEFT JOIN public.sale_order_taxes sot
              ON sot.order_id = c.order_id
             AND solt.line_id IS NULL
            INNER JOIN public.tax tx
              ON tx.tax_id = COALESCE(solt.tax_id, sot.tax_id)
            WHERE c.oj_info->>'type' = 'success'
              AND COALESCE(aml.amount_tax_total, aml.amount_tax, 0) <> 0
              AND NOT EXISTS (
                SELECT 1
                FROM public.account_move_lines_taxes existing
                WHERE existing.line_id = aml.line_id
                  AND existing.tax_id = COALESCE(solt.tax_id, sot.tax_id)
              )
            RETURNING line_id, tax_id, amount
          ),
          line_taxes_for_totals AS (
            SELECT amlt.line_id, amlt.tax_id, amlt.amount
            FROM confirmed c
            INNER JOIN public.account_move_lines aml
              ON aml.move_id = c.move_id
            INNER JOIN public.account_move_lines_taxes amlt
              ON amlt.line_id = aml.line_id
            WHERE c.oj_info->>'type' = 'success'

            UNION ALL

            SELECT line_id, tax_id, amount
            FROM repaired_line_taxes
          ),
          move_tax_rows AS MATERIALIZED (
            SELECT
              c.move_id,
              tx.tax_group_id,
              SUM(COALESCE(ltt.amount, 0)) AS amount
            FROM confirmed c
            INNER JOIN line_taxes_for_totals ltt
              ON true
            INNER JOIN public.tax tx
              ON tx.tax_id = ltt.tax_id
            WHERE c.oj_info->>'type' = 'success'
              AND NOT EXISTS (
                SELECT 1
                FROM public.account_move_taxes existing
                WHERE existing.move_id = c.move_id
                  AND existing.tax_group_id = tx.tax_group_id
              )
            GROUP BY c.move_id, tx.tax_group_id
          ),
          tax_id_lock AS (
            SELECT pg_advisory_xact_lock(hashtext('account_move_taxes.tax_id'))
          ),
          repaired_move_taxes AS (
            INSERT INTO public.account_move_taxes (
              move_id,
              tax_group_id,
              amount,
              tax_id
            )
            SELECT
              mtr.move_id,
              mtr.tax_group_id,
              mtr.amount,
              COALESCE((SELECT MAX(tax_id) FROM public.account_move_taxes), 0)
                + ROW_NUMBER() OVER (ORDER BY mtr.move_id, mtr.tax_group_id)
            FROM move_tax_rows mtr
            CROSS JOIN tax_id_lock
            RETURNING tax_id
          )
          SELECT oj_info, oj_data
          FROM confirmed
          CROSS JOIN (
            SELECT COUNT(*) AS repaired_taxes_count
            FROM repaired_move_taxes
          ) repair
        `,
        [context.orderId, context.userId, context.groupId],
      );
    } catch (error: unknown) {
      const detail = error instanceof Error ? error.stack : String(error);
      this.logger.error('Error ejecutando confirmación de orden', detail);

      if (this.getErrorCode(error) === '42883') {
        throw new InternalServerErrorException(
          'No existe la función fnc_sale_order_confirm_create_move',
        );
      }

      throw new InternalServerErrorException(
        'No se pudo confirmar la orden ni crear el borrador de facturación',
      );
    }
  }

  private toHttpException(info: DatabaseInfo) {
    const message =
      info.message ??
      info.message_text ??
      info.sqlerrm ??
      'No se pudo confirmar la orden ni crear el borrador de facturación';
    const text = [
      info.message,
      info.message_text,
      info.sqlerrm,
      info.constraint_name,
    ]
      .filter(Boolean)
      .join(' ')
      .toLowerCase();

    if (text.includes('no existe la orden')) {
      return new NotFoundException(message);
    }

    if (text.includes('permiso') || text.includes('autoriz')) {
      return new ForbiddenException(message);
    }

    if (
      text.includes('no está en estado') ||
      text.includes('pendientes por facturar') ||
      text.includes('ya confirm') ||
      text.includes('ya factur')
    ) {
      return new ConflictException(message);
    }

    if (
      text.includes('cliente') ||
      text.includes('moneda') ||
      text.includes('diario') ||
      text.includes('cantidad inválida') ||
      text.includes('residual')
    ) {
      return new BadRequestException(message);
    }

    return new InternalServerErrorException(message);
  }

  private toNumber(value: unknown): number | null {
    const numberValue = Number(value);

    return Number.isFinite(numberValue) && numberValue > 0 ? numberValue : null;
  }

  private getErrorCode(error: unknown): string | undefined {
    return typeof error === 'object' && error !== null && 'code' in error
      ? String(error.code)
      : undefined;
  }
}
