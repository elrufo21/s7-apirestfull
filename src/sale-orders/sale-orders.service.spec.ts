import {
  ConflictException,
  InternalServerErrorException,
} from '@nestjs/common';

import { SaleOrdersService } from './sale-orders.service';

describe('SaleOrdersService', () => {
  const context = {
    orderId: 10,
    userId: 7,
    groupId: 3,
    database: 'tenant_db',
  };

  const tenantDatabaseService = {
    query: jest.fn(),
  };
  const realtimeService = {
    broadcast: jest.fn(),
  };

  let service: SaleOrdersService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new SaleOrdersService(
      tenantDatabaseService as never,
      realtimeService as never,
    );
  });

  it('confirma la orden, devuelve move_id y emite realtime', async () => {
    tenantDatabaseService.query.mockResolvedValue([
      {
        oj_info: {
          code: 202,
          type: 'success',
          message: 'La orden fue confirmada y se creó el borrador.',
        },
        oj_data: { order_id: 10, move_id: 54 },
      },
    ]);

    await expect(service.confirmOrder(context)).resolves.toMatchObject({
      success: true,
      data: { order_id: 10, move_id: 54 },
    });
    expect(tenantDatabaseService.query).toHaveBeenCalledWith(
      'tenant_db',
      expect.stringContaining('fnc_sale_order_confirm_create_move'),
      [10, 7, 3],
    );
    expect(tenantDatabaseService.query.mock.calls[0][1]).toContain(
      'pg_advisory_xact_lock',
    );
    expect(tenantDatabaseService.query.mock.calls[0][1]).toContain(
      'ROW_NUMBER() OVER',
    );
    expect(realtimeService.broadcast).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'invoice.changed',
        payload: expect.objectContaining({
          action: 'confirm-sale-order',
          order_id: 10,
          move_id: 54,
        }),
      }),
    );
  });

  it('devuelve conflicto cuando la función reporta orden ya confirmada', async () => {
    tenantDatabaseService.query.mockResolvedValue([
      {
        oj_info: {
          type: 'error',
          message: 'No se pudo confirmar.',
          message_text: 'La orden de venta 10 no está en estado Borrador',
        },
        oj_data: null,
      },
    ]);

    await expect(service.confirmOrder(context)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(realtimeService.broadcast).not.toHaveBeenCalled();
  });

  it('falla si la función no devuelve filas', async () => {
    tenantDatabaseService.query.mockResolvedValue([]);

    await expect(service.confirmOrder(context)).rejects.toBeInstanceOf(
      InternalServerErrorException,
    );
  });

  it('falla claro si no existe la función SQL', async () => {
    tenantDatabaseService.query.mockRejectedValue({ code: '42883' });

    await expect(service.confirmOrder(context)).rejects.toMatchObject({
      response: expect.objectContaining({
        message: 'No existe la función fnc_sale_order_confirm_create_move',
      }),
    });
  });
});
