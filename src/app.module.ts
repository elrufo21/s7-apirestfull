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
import { RealtimeModule } from './realtime/realtime.module';
import { FilesModule } from './files/files.module';
import { SaleOrdersModule } from './sale-orders/sale-orders.module';
import { UsersModule } from './users/users.module';
import { ApisPeruModule } from './apisperu/apisperu.module';

const appEnv = process.env.APP_ENV ?? process.env.NODE_ENV;
const envFilePath = appEnv ? [`.env.${appEnv}`, '.env'] : '.env';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath,
    }),

    DatabaseModule,
    AuthDatabaseModule,
    ExecutorModule,
    AuthModule,
    TenantDatabaseModule,
    UserDataModule,
    SunatModule,
    ApisPeruModule,
    EmailModule,
    RealtimeModule,
    FilesModule,
    SaleOrdersModule,
    UsersModule,
  ],
})
export class AppModule {}
