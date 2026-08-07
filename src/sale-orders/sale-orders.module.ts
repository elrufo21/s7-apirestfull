import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { SaleOrdersController } from './sale-orders.controller';
import { SaleOrdersService } from './sale-orders.service';

@Module({
  imports: [AuthModule],
  controllers: [SaleOrdersController],
  providers: [SaleOrdersService],
})
export class SaleOrdersModule {}
