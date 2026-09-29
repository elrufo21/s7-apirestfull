import { Module } from '@nestjs/common';
import { SunatController } from './sunat.controller';
import { ApisPeruModule } from '../apisperu/apisperu.module';

@Module({
  imports: [ApisPeruModule],
  controllers: [SunatController],
})
export class SunatModule {}
