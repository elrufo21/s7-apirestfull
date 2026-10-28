import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient, QueryResultRow } from 'pg';

@Injectable()
export class TenantDatabaseService implements OnModuleDestroy {
  private readonly logger = new Logger(TenantDatabaseService.name);

  private readonly pools = new Map<string, Pool>();

  constructor(private readonly configService: ConfigService) {}

  private getPool(databaseName: string): Pool {
    const existingPool = this.pools.get(databaseName);

    if (existingPool) {
      return existingPool;
    }

    const pool = new Pool({
      host: this.configService.get<string>('TENANT_DB_HOST') || '169.58.105.101',
      port: Number(this.configService.get<string>('TENANT_DB_PORT') || 5432),
      user: this.configService.get<string>('TENANT_DB_USER') || 'postgres',
      password: this.configService.get<string>('TENANT_DB_PASSWORD') || 'linksoft2026',
      database: databaseName,

      max: 10,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
    });

    pool.on('error', (error) => {
      this.logger.error(
        `Error inesperado en la base ${databaseName}`,
        error.stack,
      );
    });

    this.pools.set(databaseName, pool);

    this.logger.log(`Pool creado para la base empresarial: ${databaseName}`);

    return pool;
  }

  async query<T extends QueryResultRow>(
    databaseName: string,
    sql: string,
    parameters: unknown[] = [],
  ): Promise<T[]> {
    const pool = this.getPool(databaseName);
    const result = await pool.query<T>(sql, parameters);

    return result.rows;
  }

  async getClient(databaseName: string): Promise<PoolClient> {
    const pool = this.getPool(databaseName);

    return pool.connect();
  }

  async onModuleDestroy(): Promise<void> {
    const closePromises = Array.from(this.pools.values()).map((pool) =>
      pool.end(),
    );

    await Promise.all(closePromises);
  }
}
