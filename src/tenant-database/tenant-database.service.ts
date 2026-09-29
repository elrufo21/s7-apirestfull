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
      host: this.configService.getOrThrow<string>('TENANT_DB_HOST'),
      port: Number(this.configService.getOrThrow<string>('TENANT_DB_PORT')),
      user: this.configService.getOrThrow<string>('TENANT_DB_USER'),
      password: this.configService.getOrThrow<string>('TENANT_DB_PASSWORD'),
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

  async transaction<T>(
    databaseName: string,
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    const client = await this.getPool(databaseName).connect();

    try {
      await client.query('BEGIN');
      const result = await callback(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async testConnection(databaseName: string): Promise<void> {
    const pool = this.getPool(databaseName);

    await pool.query('SELECT 1');

    this.logger.log(`Conexión correcta con la base: ${databaseName}`);
  }

  async onModuleDestroy(): Promise<void> {
    for (const [databaseName, pool] of this.pools.entries()) {
      await pool.end();

      this.logger.log(`Pool cerrado para la base: ${databaseName}`);
    }

    this.pools.clear();
  }
}
