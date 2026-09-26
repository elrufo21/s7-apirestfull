import { Module } from '@nestjs/common';
import { ApisPeruController } from './apisperu.controller';
import { ApisPeruService } from './apisperu.service';

@Module({
  controllers: [ApisPeruController],
  providers: [ApisPeruService],
  exports: [ApisPeruService],
})
export class ApisPeruModule {}
