import {
  BadRequestException,
  Controller,
  Param,
  ParseIntPipe,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthenticatedRequest } from '../auth/jwt-auth.guard';
import { SaleOrdersService } from './sale-orders.service';

@Controller('sale-orders')
@UseGuards(JwtAuthGuard)
export class SaleOrdersController {
  constructor(private readonly saleOrdersService: SaleOrdersService) {}

  @Post(':orderId/confirm')
  confirmOrder(
    @Param('orderId', ParseIntPipe) orderId: number,
    @Req() request: AuthenticatedRequest,
  ) {
    if (orderId <= 0) {
      throw new BadRequestException('El orderId debe ser positivo');
    }

    return this.saleOrdersService.confirmOrder({
      orderId,
      userId: request.user.userId,
      groupId: request.user.groupId,
      database: request.user.database,
    });
  }
}
