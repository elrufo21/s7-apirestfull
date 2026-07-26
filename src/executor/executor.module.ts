import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ExecutorController } from './executor.controller';
import { ExecutorService } from './executor.service';

@Module({
  imports: [AuthModule],
  controllers: [ExecutorController],
  providers: [ExecutorService],
})
export class ExecutorModule {}
