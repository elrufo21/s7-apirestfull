import { Global, Module } from '@nestjs/common';
import { TenantDatabaseService } from './tenant-database.service';

@Global()
@Module({
  providers: [TenantDatabaseService],
  exports: [TenantDatabaseService],
})
export class TenantDatabaseModule {}
