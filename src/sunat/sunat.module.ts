import { Module } from '@nestjs/common';
import { SunatController } from './sunat.controller';

@Module({
  controllers: [SunatController],
})
export class SunatModule {}
