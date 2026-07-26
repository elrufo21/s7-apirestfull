import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { DatabaseModule } from './database/database.module';
import { ExecutorModule } from './executor/executor.module';
import { AuthDatabaseModule } from './auth-database/auth-database.module';
import { AuthModule } from './auth/auth.module';
import { TenantDatabaseModule } from './tenant-database/tenant-database.module';
import { UserDataModule } from './user-data/user-data.module';
import { SunatModule } from './sunat/sunat.module';
import { EmailModule } from './email/email.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
    }),

    DatabaseModule,
    AuthDatabaseModule,
    ExecutorModule,
    AuthModule,
    TenantDatabaseModule,
    UserDataModule,
    SunatModule,
    EmailModule,
  ],
})
export class AppModule {}
